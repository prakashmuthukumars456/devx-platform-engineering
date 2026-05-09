# Outputs are how one Terraform module shares values with another.
# 02-ec2 and 03-rds will read these after vpc is applied.

output "vpc_id" {
  description = "VPC ID — needed by EC2 and RDS security groups"
  value       = aws_vpc.main.id
}

output "public_subnet_a_id" {
  description = "Public subnet A — EC2 goes here"
  value       = aws_subnet.public_a.id
}

output "public_subnet_b_id" {
  description = "Public subnet B"
  value       = aws_subnet.public_b.id
}

output "private_subnet_a_id" {
  description = "Private subnet A — RDS goes here"
  value       = aws_subnet.private_a.id
}

output "private_subnet_b_id" {
  description = "Private subnet B — RDS needs 2 AZs"
  value       = aws_subnet.private_b.id
}

output "vpc_cidr" {
  description = "VPC CIDR block"
  value       = aws_vpc.main.cidr_block
}
