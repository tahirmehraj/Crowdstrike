// main.tf
terraform {
  required_version = ">= 1.2.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 4.0"
    }
    local = {
      source  = "hashicorp/local"
      version = ">= 2.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

provider "local" {}

# -------------------------
# Minimal Security Group (VPC-scoped)
# We create just one SG in the provided VPC for EKS worker nodes and control plane communication.
# This is not creating a VPC; it is a VPC-scoped resource.
# -------------------------
resource "aws_security_group" "eks_cluster_sg" {
  name        = "${var.cluster_name}-sg"
  description = "EKS cluster security group (minimal)"
  vpc_id      = var.vpc_id
  tags        = merge(var.tags, { "Name" = "${var.cluster_name}-sg" })

  # allow worker nodes / control-plane components to talk to each other
  ingress {
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    self            = true
    description     = "Allow all traffic within SG"
  }

  # allow all outbound (you can restrict if required)
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# -------------------------
# EKS Cluster (control plane)
# Uses existing cluster role ARN provided via variable.
# -------------------------
resource "aws_eks_cluster" "this" {
  name     = var.cluster_name
  role_arn = var.cluster_role_arn
  version  = var.cluster_version

  vpc_config {
    subnet_ids         = var.subnet_ids
    security_group_ids = [aws_security_group.eks_cluster_sg.id]
    endpoint_private_access = false
    endpoint_public_access  = true
  }

  enabled_cluster_log_types = ["api", "audit", "authenticator"]
  tags = var.tags
}

# -------------------------
# EKS Managed Node Group
# Uses an existing node IAM role (node_group_role_arn).
# -------------------------
resource "aws_eks_node_group" "default" {
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "${var.cluster_name}-nodes"
  node_role_arn   = var.node_group_role_arn
  subnet_ids      = var.subnet_ids
  scaling_config {
    desired_size = var.node_desired
    min_size     = var.node_min
    max_size     = var.node_max
  }

  instance_types = [var.node_instance_type]

  tags = merge(var.tags, { "Name" = "${var.cluster_name}-ng" })

  depends_on = [
    aws_eks_cluster.this
  ]
}

# -------------------------
# Optional: kubeconfig local file generation (template)
# Helpful for tests or CI: will produce kubeconfig_{cluster_name} in this module dir.
# If you don't want files written, remove this resource.
# -------------------------
data "aws_eks_cluster" "cluster" {
  name = aws_eks_cluster.this.name
  depends_on = [aws_eks_cluster.this]
}

data "aws_eks_cluster_auth" "cluster" {
  name = aws_eks_cluster.this.name
}

resource "local_file" "kubeconfig" {
  content = templatefile("${path.module}/kubeconfig.tpl", {
    cluster_name = aws_eks_cluster.this.name
    cluster_endpoint = aws_eks_cluster.this.endpoint
    cluster_certificate_authority_data = aws_eks_cluster.this.certificate_authority[0].data
    region = var.aws_region
  })

  filename = "${path.module}/kubeconfig_${var.cluster_name}"
  depends_on = [aws_eks_cluster.this]
}
