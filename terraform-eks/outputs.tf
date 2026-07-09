output "cluster_name" {
  value       = aws_eks_cluster.eks.name
  description = "The name of the Amazon EKS cluster."
}

output "cluster_endpoint" {
  value       = aws_eks_cluster.eks.endpoint
  description = "The API server endpoint URL for the Amazon EKS cluster."
}

output "cluster_arn" {
  value       = aws_eks_cluster.eks.arn
  description = "The Amazon Resource Name (ARN) of the Amazon EKS cluster."
}

output "node_group_name" {
  value       = aws_eks_node_group.nodes.node_group_name
  description = "The name of the EKS managed node group."
}

output "vpc_id" {
  value       = aws_vpc.this.id
  description = "The ID of the provisioned VPC."
}

output "grafana_admin_password" {
  value       = var.enable_monitoring ? "admin-secret-password-123" : "Monitoring not enabled"
  description = "The administrative password for Grafana (if monitoring is enabled)."
}
