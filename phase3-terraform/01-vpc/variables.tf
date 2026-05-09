variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "project" {
  description = "Project name — used in all resource tags and names"
  type        = string
  default     = "devx"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"
}
