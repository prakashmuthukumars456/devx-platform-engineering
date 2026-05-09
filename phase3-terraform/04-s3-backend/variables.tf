variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "project" {
  type    = string
  default = "devx"
}

variable "account_id" {
  description = "Your AWS account ID — makes bucket name globally unique"
  type        = string
}
