output "instance_id" {
  value = aws_instance.app.id
}

output "public_ip" {
  description = "Public IP — use this to SSH and test endpoints"
  value       = aws_instance.app.public_ip
}

output "public_dns" {
  value = aws_instance.app.public_dns
}

output "ssh_command" {
  description = "Ready-to-use SSH command"
  value       = "ssh -i ~/.ssh/devx-key ec2-user@${aws_instance.app.public_ip}"
}

output "security_group_id" {
  description = "EC2 security group ID — RDS will allow traffic from this"
  value       = aws_security_group.ec2.id
}
