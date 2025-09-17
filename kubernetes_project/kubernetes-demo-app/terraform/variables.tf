// variables.tf
// Inputs expected from the caller. No VPC or IAM role creation here.

variable "aws_region" {
  description = "AWS region to deploy to"
  type        = string
  default     = "us-east-1"
}

variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
  default     = "demo-eks-cluster"
}

variable "cluster_version" {
  description = "Kubernetes version for EKS"
  type        = string
  default     = "1.28"
}

variable "vpc_id" {
  description = "Existing VPC ID to use for the cluster (no VPC will be created)"
  type        = string
}

variable "subnet_ids" {
  description = "List of subnet IDs (preferably private subnets across multiple AZs) for EKS vpc_config"
  type        = list(string)
}

variable "cluster_role_arn" {
  description = "ARN of an existing IAM role for the EKS cluster control plane (do not create this in Terraform per assignment)"
  type        = string
}

variable "node_group_role_arn" {
  description = "ARN of an existing IAM role to use for node group instances (do not create this in Terraform per assignment)"
  type        = string
}

variable "node_instance_type" {
  description = "EC2 instance type for the managed node group"
  type        = string
  default     = "t3.medium"
}

variable "node_desired" {
  description = "Desired capacity of the managed node group"
  type        = number
  default     = 2
}

variable "node_min" {
  description = "Min capacity for the managed node group"
  type        = number
  default     = 2
}

variable "node_max" {
  description = "Max capacity for the managed node group"
  type        = number
  default     = 10
}

variable "tags" {
  description = "Tags applied to all resources"
  type        = map(string)
  default     = { "Owner" = "dev" }
}
