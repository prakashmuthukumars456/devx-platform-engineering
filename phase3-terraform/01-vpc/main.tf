# ── Provider ──────────────────────────────────────────────────────────────────
terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  
  backend "s3" {
    bucket         = "devx-terraform-state-443938285767"
    key            = "phase4/vpc/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "devx-terraform-locks"
    encrypt        = true
  }
}

provider "aws" {
  region = var.aws_region
}

# ── VPC ───────────────────────────────────────────────────────────────────────
# The VPC is your private network in AWS.
# Everything — EC2, RDS, EKS — lives inside this VPC.
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"   # 65,536 IP addresses
  enable_dns_hostnames = true             # required for RDS and EKS
  enable_dns_support   = true

  tags = {
    Name        = "${var.project}-${var.environment}-vpc"
    Project     = var.project
    Environment = var.environment
  }
}

# ── Public Subnets ────────────────────────────────────────────────────────────
# Public subnets have a route to the internet via the IGW.
# EC2 instances go here for Phase 3.
# EKS worker nodes go here in Phase 4.
resource "aws_subnet" "public_a" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"   # 256 IPs
  availability_zone       = "${var.aws_region}a"
  map_public_ip_on_launch = true             # EC2 gets a public IP automatically

  tags = {
    Name        = "${var.project}-${var.environment}-public-a"
    Project     = var.project
    Environment = var.environment
    Type        = "public"
  }
}

resource "aws_subnet" "public_b" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "${var.aws_region}b"
  map_public_ip_on_launch = true

  tags = {
    Name        = "${var.project}-${var.environment}-public-b"
    Project     = var.project
    Environment = var.environment
    Type        = "public"
  }
}

# ── Private Subnets ───────────────────────────────────────────────────────────
# Private subnets have NO route to the internet.
# RDS goes here — database should never be publicly accessible.
# In prod, EKS worker nodes go here too (with NAT Gateway for outbound).
# We skip NAT Gateway to save cost — $32/month even when idle.
resource "aws_subnet" "private_a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.11.0/24"
  availability_zone = "${var.aws_region}a"

  tags = {
    Name        = "${var.project}-${var.environment}-private-a"
    Project     = var.project
    Environment = var.environment
    Type        = "private"
  }
}

resource "aws_subnet" "private_b" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.12.0/24"
  availability_zone = "${var.aws_region}b"

  tags = {
    Name        = "${var.project}-${var.environment}-private-b"
    Project     = var.project
    Environment = var.environment
    Type        = "private"
  }
}

# ── Internet Gateway ──────────────────────────────────────────────────────────
# The IGW is the door between your VPC and the internet.
# Without this, nothing in your VPC can reach the internet.
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name    = "${var.project}-${var.environment}-igw"
    Project = var.project
  }
}

# ── Route Tables ──────────────────────────────────────────────────────────────
# Route tables control where traffic goes.
# Public route table: traffic to 0.0.0.0/0 (internet) → IGW
# Private route table: no internet route (traffic stays in VPC)

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name    = "${var.project}-${var.environment}-public-rt"
    Project = var.project
  }
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id
  # no routes — traffic stays in VPC only

  tags = {
    Name    = "${var.project}-${var.environment}-private-rt"
    Project = var.project
  }
}

# ── Route Table Associations ──────────────────────────────────────────────────
# Associate subnets with route tables.
# Public subnets → public route table (has internet route)
# Private subnets → private route table (no internet route)

resource "aws_route_table_association" "public_a" {
  subnet_id      = aws_subnet.public_a.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public_b" {
  subnet_id      = aws_subnet.public_b.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "private_a" {
  subnet_id      = aws_subnet.private_a.id
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "private_b" {
  subnet_id      = aws_subnet.private_b.id
  route_table_id = aws_route_table.private.id
}
