variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "project" {
  type    = string
  default = "devx"
}

variable "environment" {
  type    = string
  default = "dev"
}

variable "kubernetes_version" {
  description = "EKS Kubernetes version"
  type        = string
  default     = "1.32"
}

variable "node_instance_type" {
  description = "EC2 instance type for worker nodes"
  type        = string
  default     = "t3.small"   # t3.micro too small for K8s system pods
}

variable "node_desired" {
  description = "Desired number of worker nodes"
  type        = number
  default     = 2
}

variable "node_min" {
  type    = number
  default = 1
}

variable "node_max" {
  type    = number
  default = 3
}
