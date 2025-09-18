// outputs.tf
// This file defines what information to show after Terraform creates the infrastructure

// Show the name of the EKS cluster that was created
output "cluster_name" {
  description = "EKS cluster name"
  value       = aws_eks_cluster.main_cluster.name
}

// Show the API endpoint URL where kubectl will connect
output "cluster_endpoint" {
  description = "EKS API endpoint"
  value       = aws_eks_cluster.main_cluster.endpoint
}

// Show the security certificate data (marked as sensitive so it's not displayed in logs)
output "cluster_certificate_authority_data" {
  description = "Base64 certificate authority data for the cluster"
  value       = aws_eks_cluster.main_cluster.certificate_authority[0].data
  sensitive   = true
}

// Show the name of the worker node group that was created
output "node_group_name" {
  description = "Managed node group name"
  value       = aws_eks_node_group.worker_nodes.node_group_name
}

// Show the path to the kubeconfig file that was generated
output "kubeconfig_file" {
  description = "Path to generated kubeconfig file (if local_file enabled)"
  value       = local_file.kubeconfig_file.filename
  depends_on  = [local_file.kubeconfig_file]
}