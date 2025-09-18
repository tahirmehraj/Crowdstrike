// main.tf
// This file creates the core EKS infrastructure: cluster + worker nodes

// Define which versions of Terraform and providers we need
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

// Configure the AWS provider with our chosen region
provider "aws" {
  region = var.aws_region
}

// Configure the local provider for creating files on our machine
provider "local" {}

// Create a security group to control network traffic to/from our EKS cluster
resource "aws_security_group" "cluster_security_group" {
  name        = "${var.cluster_name}-sg"
  description = "EKS cluster security group (minimal)"
  vpc_id      = var.vpc_id
  tags        = merge(var.tags, { "Name" = "${var.cluster_name}-sg" })

  // Allow all traffic between resources that have this same security group
  ingress {
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    self            = true
    description     = "Allow all traffic within SG"
  }

  // Allow all outbound traffic to the internet (for downloading container images, etc.)
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

// Create the EKS cluster (this is the Kubernetes control plane)
resource "aws_eks_cluster" "main_cluster" {
  name     = var.cluster_name
  role_arn = var.cluster_role_arn
  version  = var.cluster_version

  // Define which VPC and subnets the cluster should use
  vpc_config {
    subnet_ids         = var.subnet_ids
    security_group_ids = [aws_security_group.cluster_security_group.id]
    endpoint_private_access = true
    endpoint_public_access  = true
  }

  // Enable logging for troubleshooting
  enabled_cluster_log_types = ["api", "audit", "authenticator"]
  tags = var.tags
}

// Create a managed node group (these are the EC2 instances that run your applications)
resource "aws_eks_node_group" "worker_nodes" {
  cluster_name    = aws_eks_cluster.main_cluster.name
  node_group_name = "${var.cluster_name}-nodes"
  node_role_arn   = var.node_group_role_arn
  subnet_ids      = var.subnet_ids

  // Configure auto-scaling: how many nodes to start with, min, and max
  scaling_config {
    desired_size = var.node_desired
    min_size     = var.node_min
    max_size     = var.node_max
  }

  // What type of EC2 instances to use for the nodes
  instance_types = [var.node_instance_type]

  tags = merge(var.tags, { "Name" = "${var.cluster_name}-ng" })

  // Make sure the cluster is created before trying to create nodes
  depends_on = [
    aws_eks_cluster.main_cluster
  ]
}

// Get information about the cluster we just created (needed for kubeconfig)
data "aws_eks_cluster" "cluster_info" {
  name = aws_eks_cluster.main_cluster.name
  depends_on = [aws_eks_cluster.main_cluster]
}

// Get authentication token for the cluster (needed for kubeconfig)
data "aws_eks_cluster_auth" "cluster_auth" {
  name = aws_eks_cluster.main_cluster.name
}

// Create a kubeconfig file so kubectl can connect to our cluster
resource "local_file" "kubeconfig_file" {
  content = templatefile("${path.module}/kubeconfig.tpl", {
    cluster_name = aws_eks_cluster.main_cluster.name
    cluster_endpoint = aws_eks_cluster.main_cluster.endpoint
    cluster_certificate_authority_data = aws_eks_cluster.main_cluster.certificate_authority[0].data
    region = var.aws_region
  })

  filename = "${path.module}/kubeconfig_${var.cluster_name}"
  depends_on = [aws_eks_cluster.main_cluster]
}