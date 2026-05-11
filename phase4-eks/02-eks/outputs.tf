output "cluster_name" {
  value = aws_eks_cluster.main.name
}

output "cluster_endpoint" {
  description = "EKS API server endpoint"
  value       = aws_eks_cluster.main.endpoint
}

output "cluster_version" {
  value = aws_eks_cluster.main.version
}

output "kubeconfig_cmd" {
  description = "Run this to connect kubectl to your EKS cluster"
  value       = "aws eks update-kubeconfig --region ${var.aws_region} --name ${aws_eks_cluster.main.name}"
}

output "node_group_status" {
  value = aws_eks_node_group.main.status
}
