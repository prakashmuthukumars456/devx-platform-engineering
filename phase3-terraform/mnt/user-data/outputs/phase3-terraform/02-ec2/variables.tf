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

variable "instance_type" {
  description = "EC2 instance type — t3.micro is free tier"
  type        = string
  default     = "t3.micro"
}

variable "my_ip" {
  description = "Your IP for SSH access — run: curl ifconfig.me"
  type        = string
}

variable "public_key_path" {
  description = "Path to your SSH public key"
  type        = string
  default     = "~/.ssh/devx-key.pub"
}
