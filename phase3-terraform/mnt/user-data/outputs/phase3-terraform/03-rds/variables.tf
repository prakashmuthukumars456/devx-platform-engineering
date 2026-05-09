variable "aws_region"  { type = string; default = "us-east-1" }
variable "project"     { type = string; default = "devx" }
variable "environment" { type = string; default = "dev" }

variable "db_instance_class" {
  description = "RDS instance type — db.t3.micro is free tier"
  type        = string
  default     = "db.t3.micro"
}

variable "db_name" {
  description = "Database name"
  type        = string
  default     = "appdb"
}

variable "db_username" {
  description = "Master username"
  type        = string
  default     = "appuser"
}

variable "db_password" {
  description = "Master password — never commit real passwords"
  type        = string
  sensitive   = true
}
