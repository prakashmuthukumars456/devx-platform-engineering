output "repository_url" {
  description = "Full ECR URL — used in docker push and helm values"
  value       = aws_ecr_repository.app.repository_url
}

output "repository_name" {
  value = aws_ecr_repository.app.name
}

output "docker_login_cmd" {
  description = "Run this to authenticate docker with ECR"
  value       = "aws ecr get-login-password --region ${var.aws_region} | docker login --username AWS --password-stdin ${aws_ecr_repository.app.repository_url}"
}
