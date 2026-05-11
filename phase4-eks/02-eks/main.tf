terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.0"
    }
  }

  backend "s3" {
    bucket         = "devx-terraform-state-443938285767"
    key            = "phase4/eks/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "devx-terraform-locks"
    encrypt        = true
  }
}

provider "aws" {
  region = var.aws_region
}

# ── Read Phase 3 VPC state ────────────────────────────────────────────────────
# Reusing the same VPC from Phase 3
# EKS nodes go into public subnets (saves cost — no NAT Gateway needed)
data "terraform_remote_state" "vpc" {
  backend = "s3"
  config = {
    bucket = "devx-terraform-state-443938285767"
    key    = "phase4/vpc/terraform.tfstate"
    region = "us-east-1"
  }
}

# ── IAM Role for EKS Control Plane ───────────────────────────────────────────
# EKS control plane needs permission to manage AWS resources on your behalf.
# This role allows the EKS service to call AWS APIs.
resource "aws_iam_role" "eks_cluster" {
  name = "${var.project}-${var.environment}-eks-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "eks.amazonaws.com" }
    }]
  })

  tags = { Project = var.project }
}

resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.eks_cluster.name
}

# ── IAM Role for Node Group ───────────────────────────────────────────────────
# EC2 nodes need permissions to:
# - join the EKS cluster
# - pull images from ECR
# - send logs to CloudWatch
resource "aws_iam_role" "eks_nodes" {
  name = "${var.project}-${var.environment}-eks-nodes-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })

  tags = { Project = var.project }
}

resource "aws_iam_role_policy_attachment" "eks_worker_node" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.eks_nodes.name
}

resource "aws_iam_role_policy_attachment" "eks_cni" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.eks_nodes.name
}

resource "aws_iam_role_policy_attachment" "ecr_read" {
  # allows nodes to pull images from ECR
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.eks_nodes.name
}

resource "aws_iam_role_policy_attachment" "cloudwatch" {
  # allows nodes to send logs/metrics to CloudWatch
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
  role       = aws_iam_role.eks_nodes.name
}

# ── Security Group for EKS ────────────────────────────────────────────────────
resource "aws_security_group" "eks" {
  name        = "${var.project}-${var.environment}-eks-sg"
  description = "EKS cluster security group"
  vpc_id      = data.terraform_remote_state.vpc.outputs.vpc_id

  ingress {
    from_port = 443
    to_port   = 443
    protocol  = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "K8s API server"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project}-${var.environment}-eks-sg" }
}

# ── EKS Cluster ───────────────────────────────────────────────────────────────
# The control plane — managed by AWS, you pay $0.10/hr
# AWS handles: etcd, API server, scheduler, controller manager
# You only manage: worker nodes and what runs on them
resource "aws_eks_cluster" "main" {
  name     = "${var.project}-${var.environment}-cluster"
  role_arn = aws_iam_role.eks_cluster.arn
  version  = var.kubernetes_version

  vpc_config {
    subnet_ids              = [
      data.terraform_remote_state.vpc.outputs.public_subnet_a_id,
      data.terraform_remote_state.vpc.outputs.public_subnet_b_id,
    ]
    security_group_ids      = [aws_security_group.eks.id]
    endpoint_public_access  = true   # kubectl works from your laptop
    endpoint_private_access = true   # nodes communicate internally
  }

  depends_on = [aws_iam_role_policy_attachment.eks_cluster_policy]

  tags = {
    Name        = "${var.project}-${var.environment}-cluster"
    Project     = var.project
    Environment = var.environment
  }
}

# ── EKS Node Group ────────────────────────────────────────────────────────────
# Worker nodes — EC2 instances that run your pods
# Managed node group = AWS handles OS updates and node lifecycle
resource "aws_eks_node_group" "main" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "${var.project}-${var.environment}-nodes"
  node_role_arn   = aws_iam_role.eks_nodes.arn

  subnet_ids = [
    data.terraform_remote_state.vpc.outputs.public_subnet_a_id,
    data.terraform_remote_state.vpc.outputs.public_subnet_b_id,
  ]

  instance_types = [var.node_instance_type]

  scaling_config {
    desired_size = var.node_desired
    min_size     = var.node_min
    max_size     = var.node_max
  }

  update_config {
    max_unavailable = 1   # rolling update — always 1 node available
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_worker_node,
    aws_iam_role_policy_attachment.eks_cni,
    aws_iam_role_policy_attachment.ecr_read,
  ]

  tags = {
    Name    = "${var.project}-${var.environment}-node"
    Project = var.project
  }
}
