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
    key            = "phase4/observability/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "devx-terraform-locks"
    encrypt        = true
  }
}

provider "aws" {
  region = var.aws_region
}

data "terraform_remote_state" "eks" {
  backend = "s3"
  config = {
    bucket = "devx-terraform-state-443938285767"
    key    = "phase4/eks/terraform.tfstate"
    region = "us-east-1"
  }
}

# ── Enable CloudWatch Container Insights ──────────────────────────────────────
# Container Insights gives you:
# - CPU and memory usage per pod
# - Network traffic
# - Container restarts
# - Node health
# This replaces New Relic for AWS-native observability
resource "aws_eks_addon" "cloudwatch" {
  cluster_name = data.terraform_remote_state.eks.outputs.cluster_name
  addon_name   = "amazon-cloudwatch-observability"

  tags = {
    Project     = var.project
    Environment = var.environment
  }
}

# ── CloudWatch Log Group ──────────────────────────────────────────────────────
# Stores application logs from all pods.
# Retention set to 7 days for cost control.
resource "aws_cloudwatch_log_group" "eks" {
  name              = "/aws/eks/${var.project}-${var.environment}/cluster"
  retention_in_days = 7

  tags = {
    Project     = var.project
    Environment = var.environment
  }
}

# ── CloudWatch Alarm — pod restarts ──────────────────────────────────────────
# Fires when any pod restarts more than 5 times in 5 minutes.
# This is your liveness probe failure detector.
resource "aws_cloudwatch_metric_alarm" "pod_restarts" {
  alarm_name          = "${var.project}-${var.environment}-pod-restarts"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "pod_number_of_container_restarts"
  namespace           = "ContainerInsights"
  period              = 300
  statistic           = "Sum"
  threshold           = 5
  alarm_description   = "Pod restarting too frequently"

  dimensions = {
    ClusterName = data.terraform_remote_state.eks.outputs.cluster_name
  }

  tags = {
    Project     = var.project
    Environment = var.environment
  }
}
