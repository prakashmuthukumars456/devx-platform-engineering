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

# ── S3 Bucket for Terraform State ─────────────────────────────────────────────
# Right now state lives in local .tfstate files.
# Problem: they can't be shared, can be lost, no locking.
# Solution: store state in S3 — accessible from anywhere, versioned.
# Phase 4 (EKS) will use this bucket for its state too.
resource "aws_s3_bucket" "terraform_state" {
  # Bucket names must be globally unique across all AWS accounts
  bucket        = "${var.project}-terraform-state-${var.account_id}"
  force_destroy = true   # allows bucket deletion even with files inside

  tags = {
    Name    = "terraform-state"
    Project = var.project
  }
}

resource "aws_s3_bucket_versioning" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id
  versioning_configuration {
    status = "Enabled"   # keeps history of every state change — great for rollback
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"   # encrypt state at rest
    }
  }
}

resource "aws_s3_bucket_public_access_block" "terraform_state" {
  bucket                  = aws_s3_bucket.terraform_state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ── DynamoDB Table for State Locking ──────────────────────────────────────────
# When two people run terraform apply simultaneously, they'd corrupt the state.
# DynamoDB provides a lock — only one apply can run at a time.
resource "aws_dynamodb_table" "terraform_locks" {
  name         = "${var.project}-terraform-locks"
  billing_mode = "PAY_PER_REQUEST"   # no capacity to provision, pay only when used
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  tags = {
    Name    = "terraform-state-locks"
    Project = var.project
  }
}
