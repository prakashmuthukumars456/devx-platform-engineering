# Phase 3 — Terraform

Provision AWS infrastructure using Terraform.
Each folder is an independent module — apply and destroy separately.

## Folder structure

```
phase3-terraform/
├── 01-vpc/          # VPC, subnets, IGW, route tables
├── 02-ec2/          # EC2 instance, security group, key pair
├── 03-rds/          # RDS postgres in private subnet
└── 04-s3-backend/   # S3 + DynamoDB for remote state (used in Phase 4)
```

## What each module creates

| Module | AWS Resources | Cost |
|---|---|---|
| 01-vpc | VPC, 4 subnets, IGW, 2 route tables | Free |
| 02-ec2 | t3.micro instance, security group, key pair | ~$0.01/hr |
| 03-rds | db.t3.micro postgres, subnet group, parameter group | ~$0.02/hr |
| 04-s3-backend | S3 bucket, DynamoDB table | ~$0/mo (nearly free) |

**Always `terraform destroy` after each session — EC2 + RDS cost money when running.**

## Prerequisites

### 1. Create SSH key pair

```bash
ssh-keygen -t rsa -b 4096 -f ~/.ssh/devx-key -N ""
# Creates: ~/.ssh/devx-key (private) and ~/.ssh/devx-key.pub (public)
```

### 2. Get your current IP

```bash
curl ifconfig.me
# Add /32 to make it a CIDR: e.g. 103.21.45.67/32
# Update my_ip in 02-ec2/terraform.tfvars
```

## Deploy order

```
04-s3-backend  → (optional, do first to get remote state ready)
01-vpc         → must be first (everything else depends on it)
02-ec2         → depends on 01-vpc outputs
03-rds         → depends on 01-vpc + 02-ec2 outputs
```

## Commands per module

```bash
# Navigate into module folder
cd 01-vpc

# Initialise — downloads AWS provider
terraform init

# Preview what will be created (no changes made)
terraform plan

# Apply — creates resources in AWS
terraform apply

# See what was created
terraform output

# Destroy — deletes everything (do this after each session)
terraform destroy
```

## Full deploy sequence

```bash
# Step 1 — S3 backend (one-time setup)
cd phase3-terraform/04-s3-backend
terraform init && terraform apply

# Step 2 — VPC
cd ../01-vpc
terraform init && terraform apply

# Step 3 — EC2
cd ../02-ec2
terraform init && terraform apply
terraform output ssh_command   # get your SSH command

# Step 4 — RDS (takes ~5 min to provision)
cd ../03-rds
terraform init && terraform apply
terraform output db_endpoint   # get your DB endpoint
```

## After EC2 is up — connect and run your app

```bash
# SSH into the instance
ssh -i ~/.ssh/devx-key ec2-user@<public_ip>

# Clone your repo
git clone https://github.com/prakashmuthukumars456/devx-platform-engineering.git
cd devx-platform-engineering/phase1-docker

# Create .env pointing to RDS
cat > .env << EOF
APP_NAME=fastapi-k8s-app
APP_ENV=production
DEBUG=false
POSTGRES_HOST=<rds_endpoint>
POSTGRES_PORT=5432
POSTGRES_USER=appuser
POSTGRES_PASSWORD=DevxPassword123!
POSTGRES_DB=appdb
REDIS_HOST=localhost
REDIS_PORT=6379
REDIS_PASSWORD=redispassword
EOF

# Run app (without postgres since RDS handles that)
docker-compose up -d app redis
curl http://localhost:8000/health
```

## Key Terraform concepts in this phase

| Concept | Where used | What it does |
|---|---|---|
| `resource` | all modules | creates an AWS resource |
| `variable` | variables.tf | parameterises the config |
| `output` | outputs.tf | exports values for other modules |
| `data` | 02-ec2, 03-rds | reads existing state or AWS data |
| `terraform_remote_state` | 02-ec2, 03-rds | reads outputs from another module |
| `terraform init` | first command | downloads providers |
| `terraform plan` | before apply | preview changes |
| `terraform apply` | deploy | creates resources |
| `terraform destroy` | cleanup | deletes everything |

## Destroy order (reverse of deploy)

```bash
cd 03-rds    && terraform destroy
cd ../02-ec2 && terraform destroy
cd ../01-vpc && terraform destroy
# Keep 04-s3-backend for Phase 4
```
