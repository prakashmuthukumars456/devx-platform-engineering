terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# ── Read VPC and EC2 outputs ──────────────────────────────────────────────────
data "terraform_remote_state" "vpc" {
  backend = "local"
  config  = { path = "../01-vpc/terraform.tfstate" }
}

data "terraform_remote_state" "ec2" {
  backend = "local"
  config  = { path = "../02-ec2/terraform.tfstate" }
}

# ── DB Subnet Group ───────────────────────────────────────────────────────────
# RDS requires a subnet group — a list of subnets across 2+ AZs.
# RDS is placed in private subnets so it's not internet-accessible.
resource "aws_db_subnet_group" "main" {
  name        = "${var.project}-${var.environment}-db-subnet-group"
  description = "RDS subnet group — private subnets only"
  subnet_ids  = [
    data.terraform_remote_state.vpc.outputs.private_subnet_a_id,
    data.terraform_remote_state.vpc.outputs.private_subnet_b_id,
  ]

  tags = {
    Name    = "${var.project}-${var.environment}-db-subnet-group"
    Project = var.project
  }
}

# ── RDS Security Group ────────────────────────────────────────────────────────
# Only allow postgres traffic FROM the EC2 security group.
# Not from the internet — only your EC2 instance can reach the database.
resource "aws_security_group" "rds" {
  name        = "${var.project}-${var.environment}-rds-sg"
  description = "RDS security group — only EC2 can connect"
  vpc_id      = data.terraform_remote_state.vpc.outputs.vpc_id

  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [data.terraform_remote_state.ec2.outputs.security_group_id]
    description     = "Postgres from EC2 only"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${var.project}-${var.environment}-rds-sg"
    Project     = var.project
    Environment = var.environment
  }
}

# ── RDS Parameter Group ───────────────────────────────────────────────────────
# Parameter groups control postgres configuration.
# Using defaults for now — in prod you'd tune here.
resource "aws_db_parameter_group" "main" {
  name        = "${var.project}-${var.environment}-pg16"
  family      = "postgres16"
  description = "Postgres 16 parameter group"

  tags = {
    Name    = "${var.project}-${var.environment}-pg16"
    Project = var.project
  }
}

# ── RDS Instance ──────────────────────────────────────────────────────────────
# db.t3.micro = free tier eligible
# single-AZ = no standby replica (saves cost for learning)
# No multi-az, no read replica — keep it simple for Phase 3
resource "aws_db_instance" "main" {
  identifier        = "${var.project}-${var.environment}-postgres"
  engine            = "postgres"
  engine_version    = "16.3"
  instance_class    = var.db_instance_class
  allocated_storage = 20         # 20GB — free tier includes 20GB
  storage_type      = "gp2"

  db_name  = var.db_name
  username = var.db_username
  password = var.db_password

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  parameter_group_name   = aws_db_parameter_group.main.name

  # Important cost/learning settings
  multi_az                = false   # single-AZ saves cost
  publicly_accessible     = false   # private subnet only
  skip_final_snapshot     = true    # allows destroy without manual snapshot
  deletion_protection     = false   # allows terraform destroy cleanly
  backup_retention_period = 0       # no backups for learning (saves cost)

  tags = {
    Name        = "${var.project}-${var.environment}-postgres"
    Project     = var.project
    Environment = var.environment
  }
}
