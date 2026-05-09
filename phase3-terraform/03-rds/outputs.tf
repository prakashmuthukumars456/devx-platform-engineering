output "db_endpoint" {
  description = "RDS endpoint — use this as POSTGRES_HOST in your app"
  value       = aws_db_instance.main.endpoint
}

output "db_name" {
  value = aws_db_instance.main.db_name
}

output "db_port" {
  value = aws_db_instance.main.port
}

output "db_connection_string" {
  description = "Connection string for psql (password not included)"
  value       = "postgresql://${var.db_username}@${aws_db_instance.main.endpoint}/${var.db_name}"
  sensitive   = true
}
