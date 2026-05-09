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

# ── Read VPC outputs ──────────────────────────────────────────────────────────
# terraform_remote_state reads outputs from another module's state file.
# After applying 01-vpc, its state is saved in 01-vpc/terraform.tfstate.
# This block reads vpc_id, subnet IDs etc from that state.
data "terraform_remote_state" "vpc" {
  backend = "local"
  config = {
    path = "../01-vpc/terraform.tfstate"
  }
}

# ── Latest Amazon Linux 2023 AMI ──────────────────────────────────────────────
# Instead of hardcoding an AMI ID (which changes per region),
# we query AWS to find the latest Amazon Linux 2023 AMI dynamically.
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# ── Key Pair ──────────────────────────────────────────────────────────────────
# SSH key pair for connecting to the EC2 instance.
# We generate the key locally and upload the PUBLIC key to AWS.
# The PRIVATE key stays on your machine only.
resource "aws_key_pair" "devx" {
  key_name   = "${var.project}-${var.environment}-key"
  public_key = file(var.public_key_path)

  tags = {
    Name    = "${var.project}-${var.environment}-key"
    Project = var.project
  }
}

# ── Security Group ────────────────────────────────────────────────────────────
# Security groups are stateful firewalls at the instance level.
# Inbound rules: what traffic is allowed IN
# Outbound rules: what traffic is allowed OUT
resource "aws_security_group" "ec2" {
  name        = "${var.project}-${var.environment}-ec2-sg"
  description = "Security group for devx EC2 instance"
  vpc_id      = data.terraform_remote_state.vpc.outputs.vpc_id

  # SSH — only from your IP
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.my_ip]
    description = "SSH from my IP only"
  }

  # HTTP — for testing the FastAPI app
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTP public"
  }

  # FastAPI port — direct access for testing
  ingress {
    from_port   = 8000
    to_port     = 8000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "FastAPI direct"
  }

  # All outbound traffic allowed
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "All outbound allowed"
  }

  tags = {
    Name        = "${var.project}-${var.environment}-ec2-sg"
    Project     = var.project
    Environment = var.environment
  }
}

# ── EC2 Instance ──────────────────────────────────────────────────────────────
# t3.micro = free tier eligible, 2 vCPU, 1GB RAM
# Enough for running our FastAPI app + connecting to RDS
resource "aws_instance" "app" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = var.instance_type
  subnet_id              = data.terraform_remote_state.vpc.outputs.public_subnet_a_id
  vpc_security_group_ids = [aws_security_group.ec2.id]
  key_name               = aws_key_pair.devx.key_name

  # user_data runs on first boot — installs Docker so we can run our app
  user_data = <<-EOF
    #!/bin/bash
    yum update -y
    yum install -y docker git
    systemctl start docker
    systemctl enable docker
    usermod -aG docker ec2-user

    # Install docker compose
    curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-linux-x86_64" \
      -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose

    echo "Bootstrap complete" > /tmp/bootstrap.log
  EOF

  tags = {
    Name        = "${var.project}-${var.environment}-app"
    Project     = var.project
    Environment = var.environment
  }
}
