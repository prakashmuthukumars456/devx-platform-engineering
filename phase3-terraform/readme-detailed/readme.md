# Phase 3 — Terraform File by File Reference

---

## 04-s3-backend

### main.tf — 3 resources
Creates S3 bucket (versioned, AES256 encrypted, public access blocked) and DynamoDB table for state locking. Bucket name includes your account ID 443938285767 to be globally unique across all AWS accounts.

```hcl
resource "aws_s3_bucket" "terraform_state" {
  bucket = "devx-terraform-state-443938285767"
}
resource "aws_dynamodb_table" "terraform_locks" {
  name     = "devx-terraform-locks"
  hash_key = "LockID"
}
```
**Creates:** S3 bucket + DynamoDB table

---

### variables.tf — aws_region, project, account_id
account_id is the key variable here — it makes the S3 bucket name globally unique. No two S3 buckets anywhere in AWS can share the same name.

```hcl
variable "account_id" {
  type = string
}
```
**Creates:** no AWS resource — just inputs

---

### outputs.tf — bucket_name, backend_config
backend_config output is a ready-to-paste S3 backend block. Phase 4 EKS copies this into its terraform block so both phases share one state bucket.

```hcl
output "backend_config" {
  value = "backend s3 { bucket=devx-terraform-state-443938285767 key=phase4-eks/... }"
}
```
**Creates:** no AWS resource — exports values for Phase 4

---

### terraform.tfvars — actual values
Supplies the real values. account_id 443938285767 is your AWS account from `aws sts get-caller-identity`.

```hcl
aws_region = "us-east-1"
project    = "devx"
account_id = "443938285767"
```
**Creates:** no AWS resource — feeds variables

---

## 01-vpc

### main.tf — 9 resources
Creates the entire network: VPC (10.0.0.0/16), 2 public subnets for EC2 (10.0.1/2.0/24), 2 private subnets for RDS (10.0.11/12.0/24), internet gateway, public route table with 0.0.0.0/0 to IGW, private route table with no internet route, and 4 route table associations.

```hcl
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
}
resource "aws_subnet" "public_a" {
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true
}
resource "aws_subnet" "private_a" {
  cidr_block = "10.0.11.0/24"
}
```
**Creates:** vpc-0a38ffd9e2a45fe5f, 4 subnets, IGW, 2 route tables

---

### outputs.tf — vpc_id + 4 subnet IDs
These 6 outputs are what every other module reads. Without them 02-ec2 and 03-rds have no idea where to place themselves in AWS. This is the foundation everything else reads.

```hcl
output "vpc_id" {
  value = aws_vpc.main.id
}
output "public_subnet_a_id" {
  value = aws_subnet.public_a.id
}
output "private_subnet_a_id" {
  value = aws_subnet.private_a.id
}
```
**Creates:** no AWS resource — exports IDs for other modules

---

## 02-ec2

### main.tf — data: vpc state + ami lookup
Two data sources before any resource. terraform_remote_state reads 01-vpc outputs to get subnet IDs. aws_ami dynamically queries AWS for the latest Amazon Linux 2023 AMI so you never hardcode an AMI ID that changes by region.

```hcl
data "terraform_remote_state" "vpc" {
  backend = "local"
  config  = { path = "../01-vpc/terraform.tfstate" }
}
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]
  filter { name = "name" values = ["al2023-ami-*"] }
}
```
**Creates:** no resource — reads existing data

---

### main.tf — aws_key_pair
Uploads your ~/.ssh/devx-key.pub public key to AWS. EC2 uses this to allow SSH login. Your private key ~/.ssh/devx-key never leaves your machine — AWS only ever sees the public key.

```hcl
resource "aws_key_pair" "devx" {
  key_name   = "devx-dev-key"
  public_key = file("~/.ssh/devx-key.pub")
}
```
**Creates:** devx-dev-key

---

### main.tf — aws_security_group
Stateful firewall for EC2. Allows port 22 (SSH) from your IP only, ports 80 and 8000 from anywhere for testing FastAPI. All outbound traffic allowed. The security_group_id output from this resource is what RDS reads to restrict its access.

```hcl
ingress {
  from_port   = 22
  cidr_blocks = [var.my_ip]  # your IP only
}
ingress {
  from_port   = 8000
  cidr_blocks = ["0.0.0.0/0"]
}
```
**Creates:** sg-067acb0130e2e6576

---

### main.tf — aws_instance
The EC2 machine itself. t3.micro in public_subnet_a (read from VPC remote state). user_data script runs on first boot and installs Docker + docker-compose automatically. Public IP assigned because the subnet has map_public_ip_on_launch=true.

```hcl
resource "aws_instance" "app" {
  ami           = data.aws_ami.amazon_linux.id
  instance_type = "t3.micro"
  subnet_id     = data.terraform_remote_state
                    .vpc.outputs.public_subnet_a_id
  user_data     = "#!/bin/bash\nyum install -y docker"
}
```
**Creates:** i-06827ed87143b0da4 — public IP 32.197.197.208

---

### outputs.tf — public_ip, ssh_command, sg_id
ssh_command is a ready-to-run string. security_group_id is the critical output — 03-rds reads this to only allow EC2 through to postgres port 5432.

```hcl
output "ssh_command" {
  value = "ssh -i ~/.ssh/devx-key ec2-user@${aws_instance.app.public_ip}"
}
output "security_group_id" {
  value = aws_security_group.ec2.id
}
```
**Creates:** no AWS resource — exports for use by 03-rds

---

## 03-rds

### main.tf — data: vpc + ec2 state
Reads BOTH vpc and ec2 remote state. Needs private subnet IDs from vpc for placing RDS in private subnets, and security_group_id from ec2 for the RDS firewall rule. This is why deploy order matters — both must exist before RDS.

```hcl
data "terraform_remote_state" "vpc" {
  config = { path = "../01-vpc/terraform.tfstate" }
}
data "terraform_remote_state" "ec2" {
  config = { path = "../02-ec2/terraform.tfstate" }
}
```
**Creates:** no resource — reads vpc + ec2 outputs

---

### main.tf — aws_db_subnet_group
Lists the 2 private subnets for RDS placement. RDS requires subnets in at least 2 availability zones. By using private subnets here, RDS is guaranteed to never be in a public subnet.

```hcl
resource "aws_db_subnet_group" "main" {
  subnet_ids = [
    data.terraform_remote_state.vpc.outputs.private_subnet_a_id,
    data.terraform_remote_state.vpc.outputs.private_subnet_b_id,
  ]
}
```
**Creates:** devx-dev-db-subnet-group

---

### main.tf — aws_security_group for RDS

> **Most important security rule in Phase 3.**

Port 5432 allowed ONLY from the EC2 security group ID — not from 0.0.0.0/0. This means the internet cannot reach your database. Only your EC2 instance can. This is the standard production security pattern.

```hcl
ingress {
  from_port = 5432
  protocol  = "tcp"
  security_groups = [
    data.terraform_remote_state.ec2
      .outputs.security_group_id  # EC2 only
  ]
  # NOT cidr_blocks = ["0.0.0.0/0"]
}
```
**Creates:** devx-dev-rds-sg

---

### main.tf — aws_db_instance
The actual RDS postgres database. db.t3.micro is free tier. publicly_accessible=false means no public endpoint. skip_final_snapshot=true and deletion_protection=false allow clean terraform destroy without manual steps.

```hcl
resource "aws_db_instance" "main" {
  engine              = "postgres"
  engine_version      = "16.3"
  instance_class      = "db.t3.micro"
  allocated_storage   = 20
  publicly_accessible = false
  skip_final_snapshot = true
}
```
**Creates:** devx-dev-postgres — endpoint used as POSTGRES_HOST

---

### outputs.tf — db_endpoint
db_endpoint is the RDS hostname you pasted into .env on EC2 as POSTGRES_HOST. The same Phase 1 FastAPI app connects to this without any code changes — just a different hostname in the environment variable.

```hcl
output "db_endpoint" {
  value = aws_db_instance.main.endpoint
}
# devx-dev-postgres.car8wuy4misw.us-east-1.rds.amazonaws.com
```
**Creates:** no AWS resource — exports connection details for app

---

## How modules connect

```
04-s3-backend  →  Phase 4 EKS reads bucket name for remote state
01-vpc         →  02-ec2 reads vpc_id + public_subnet_a_id
01-vpc         →  03-rds reads vpc_id + private_subnet_a/b_id
02-ec2         →  03-rds reads security_group_id (locks RDS to EC2 only)
03-rds         →  your .env reads db_endpoint as POSTGRES_HOST
```

## Deploy order

```bash
cd 04-s3-backend && terraform init && terraform apply
cd ../01-vpc     && terraform init && terraform apply
cd ../02-ec2     && terraform init && terraform apply
cd ../03-rds     && terraform init && terraform apply
```

## Destroy order (always reverse)

```bash
cd 03-rds    && terraform destroy -auto-approve
cd ../02-ec2 && terraform destroy -auto-approve
cd ../01-vpc && terraform destroy -auto-approve
# keep 04-s3-backend for Phase 4
```
