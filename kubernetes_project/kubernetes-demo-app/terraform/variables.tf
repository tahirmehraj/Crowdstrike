// variables.tf
// This file defines all the input parameters that can be customized when running Terraform

// Which AWS region to create resources in (like us-east-1, us-west-2, etc.)
variable "aws_region" {
  description = "AWS region to deploy to"
  type        = string
  default     = "us-east-1"
}

// What to name your EKS cluster (will appear in AWS console)
variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
  default     = "demo-eks-cluster"
}

// Which version of Kubernetes to install (1.28, 1.29, etc.)
variable "cluster_version" {
  description = "Kubernetes version for EKS"
  type        = string
  default     = "1.28"
}

// ID of an existing VPC where the cluster will be created (must already exist)
variable "vpc_id" {
  description = "Existing VPC ID to use for the cluster (no VPC will be created)"
  type        = string
}

// List of existing subnet IDs where worker nodes will be placed (must already exist)
variable "subnet_ids" {
  description = "List of subnet IDs (preferably private subnets across multiple AZs) for EKS vpc_config"
  type        = list(string)
}

// ARN of existing IAM role that gives EKS permission to manage the cluster (must already exist)
variable "cluster_role_arn" {
  description = "ARN of an existing IAM role for the EKS cluster control plane (do not create this in Terraform per assignment)"
  type        = string
}

// ARN of existing IAM role that gives worker nodes permission to join cluster (must already exist)
variable "node_group_role_arn" {
  description = "ARN of an existing IAM role to use for node group instances (do not create this in Terraform per assignment)"
  type        = string
}

// What type of EC2 instances to use for worker nodes (t3.medium, m5.large, etc.)
variable "node_instance_type" {
  description = "EC2 instance type for the managed node group"
  type        = string
  default     = "t3.medium"
}

// How many worker nodes to start with
variable "node_desired" {
  description = "Desired capacity of the managed node group"
  type        = number
  default     = 2
}

// Minimum number of worker nodes (auto-scaling won't go below this)
variable "node_min" {
  description = "Min capacity for the managed node group"
  type        = number
  default     = 2
}

// Maximum number of worker nodes (auto-scaling won't go above this)
variable "node_max" {
  description = "Max capacity for the managed node group"
  type        = number
  default     = 4
}

// Tags to apply to all AWS resources (for organization and billing)
variable "tags" {
  description = "Tags applied to all resources"
  type        = map(string)
  default     = { "Owner" = "dev" }
}