# Phase 4 — EKS File by File Reference

---

## 01-ecr

### main.tf — ECR repository + lifecycle policy
Creates a private Docker registry inside your AWS account. EKS pulls images from here instead of Docker Hub. Lifecycle policy auto-deletes untagged images after 1 day to save storage cost.

```hcl
resource "aws_ecr_repository" "app" {
  name                 = "devx-dev-app"
  image_tag_mutability = "MUTABLE"
  image_scanning_configuration {
    scan_on_push = true       # CVE scan on every push
  }
}
```
**Creates:** `443938285767.dkr.ecr.us-east-1.amazonaws.com/devx-dev-app`

### outputs.tf — repository_url, docker_login_cmd
`repository_url` is the full ECR address you use in `docker tag` and `docker push`. `docker_login_cmd` authenticates Docker with ECR — must run before every push session since the token expires after 12 hours.

```hcl
output "docker_login_cmd" {
  value = "aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin ${aws_ecr_repository.app.repository_url}"
}
```

---

## 02-eks

### main.tf — data: VPC remote state
Reads VPC outputs from S3 backend (migrated in Phase 3). EKS subnets come from this — public for control plane, public for nodes (cost-optimised).

```hcl
data "terraform_remote_state" "vpc" {
  backend = "s3"
  config = {
    bucket = "devx-terraform-state-443938285767"
    key    = "phase4/vpc/terraform.tfstate"
    region = "us-east-1"
  }
}
```

### main.tf — aws_iam_role.eks_cluster (control plane role)
The EKS control plane (API server, scheduler, controller manager) runs as an AWS-managed service. It needs permission to call AWS APIs to create load balancers, manage network interfaces, etc.

```hcl
resource "aws_iam_role" "eks_cluster" {
  assume_role_policy = jsonencode({
    Statement = [{
      Action    = "sts:AssumeRole"
      Principal = { Service = "eks.amazonaws.com" }
    }]
  })
}
resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.eks_cluster.name
}
```
**Without this:** EKS cluster cannot be created.

### main.tf — aws_iam_role.eks_nodes (worker node role)
EC2 worker nodes need 4 separate permissions. Each is a policy attachment. Missing any one causes a specific failure mode.

```hcl
# Required to join the cluster
AmazonEKSWorkerNodePolicy

# Required for pod networking (VPC CNI)
AmazonEKS_CNI_Policy

# Required to pull images from ECR
AmazonEC2ContainerRegistryReadOnly

# Required to send logs/metrics to CloudWatch
CloudWatchAgentServerPolicy
```
**Without ecr_read:** Pods stuck in `ImagePullBackOff` forever.

### main.tf — aws_security_group.eks
Opens port 443 from anywhere so kubectl on your laptop can reach the EKS API. Works together with `endpoint_public_access = true` in cluster config.

```hcl
ingress {
  from_port   = 443
  protocol    = "tcp"
  cidr_blocks = ["0.0.0.0/0"]
  description = "K8s API server"
}
```

### main.tf — aws_eks_cluster.main
The control plane itself. AWS manages etcd, API server, scheduler, controller manager. You pay $0.10/hr. `endpoint_public_access` enables kubectl from outside, `endpoint_private_access` enables node-to-control-plane comms.

```hcl
resource "aws_eks_cluster" "main" {
  name     = "devx-dev-cluster"
  role_arn = aws_iam_role.eks_cluster.arn
  version  = "1.32"
  vpc_config {
    subnet_ids             = [public_a, public_b]
    endpoint_public_access = true
    endpoint_private_access= true
  }
}
```
**Cost:** $0.10/hr (~$73/month if left running)

### main.tf — aws_eks_node_group.main
2x t3.small EC2 instances as worker nodes. Managed node group = AWS handles OS updates. `max_unavailable: 1` ensures rolling updates keep at least one node serving traffic.

```hcl
resource "aws_eks_node_group" "main" {
  cluster_name   = aws_eks_cluster.main.name
  instance_types = ["t3.small"]
  scaling_config {
    desired_size = 2
    min_size     = 1
    max_size     = 3
  }
  update_config {
    max_unavailable = 1
  }
}
```
**Cost:** $0.046/hr for 2x t3.small

### outputs.tf — kubeconfig_cmd
The single most useful output. Updates `~/.kube/config` to point kubectl at your EKS cluster instead of Docker Desktop.

```hcl
output "kubeconfig_cmd" {
  value = "aws eks update-kubeconfig --region us-east-1 --name devx-dev-cluster"
}
```

---

## 03-helm

### values-eks.yaml — EKS-specific overrides
Same Helm chart from Phase 2. Only the values change for EKS deployment.

| Key | Phase 2 (local) | Phase 4 (EKS) |
|---|---|---|
| image.repository | `fastapi-k8s-app-app` | ECR full URL |
| image.pullPolicy | `Never` (local image) | `Always` (pull from ECR) |
| service.type | LoadBalancer (= localhost) | LoadBalancer (= AWS ELB) |
| APP_ENV | `development` | `production` |
| DEBUG | `true` (show /docs) | `false` (hide /docs) |
| POSTGRES_HOST | `postgres-service` | `postgres-service` (in-cluster) |

---

## 04-observability

### main.tf — aws_eks_addon (CloudWatch Container Insights)
AWS-managed addon that ships pod metrics, container logs, and cluster events to CloudWatch automatically.

```hcl
resource "aws_eks_addon" "cloudwatch" {
  cluster_name = data.terraform_remote_state.eks.outputs.cluster_name
  addon_name   = "amazon-cloudwatch-observability"
}
```
**Gives you:** CPU/memory per pod, container restarts, node health — all in CloudWatch console.

---

## How Phase 4 modules connect

```
04-s3-backend   →   stores all terraform state files in S3 bucket
       ↓
01-vpc (Phase 3) →  state migrated to S3, reused for EKS
       ↓
01-ecr           →   stores Docker images for EKS to pull
       ↓
docker push      →   pushes image to ECR
       ↓
02-eks           →   creates cluster + node group (reads VPC state)
       ↓
helm install     →   deploys app to cluster (pulls image from ECR)
       ↓
LoadBalancer     →   AWS ELB routes traffic to fastapi pods
       ↓
04-observability →   enables CloudWatch monitoring
```

---

## Deploy commands in order

```bash
# Step 0 — verify S3 backend exists (from Phase 3)
cd phase3-terraform/04-s3-backend && terraform output bucket_name

# Step 1 — recreate VPC with S3 backend
cd ../01-vpc
terraform init -migrate-state    # moves state from local to S3
terraform apply -auto-approve

# Step 2 — create ECR
cd ../../phase4-eks/01-ecr
terraform init && terraform apply -auto-approve

# Step 3 — build and push image to ECR
cd ../../phase1-docker
$(terraform -chdir=../phase4-eks/01-ecr output -raw docker_login_cmd)
docker build -t devx-dev-app .
docker tag devx-dev-app:latest 443938285767.dkr.ecr.us-east-1.amazonaws.com/devx-dev-app:latest
docker push 443938285767.dkr.ecr.us-east-1.amazonaws.com/devx-dev-app:latest

# Step 4 — create EKS cluster (15-20 min)
cd ../phase4-eks/02-eks
terraform init && terraform apply -auto-approve

# Step 5 — connect kubectl to EKS
$(terraform output -raw kubeconfig_cmd)
kubectl get nodes    # should show 2 nodes Ready

# Step 6 — set up IRSA for EBS CSI driver
eksctl utils associate-iam-oidc-provider \
  --region us-east-1 \
  --cluster devx-dev-cluster \
  --approve

eksctl create iamserviceaccount \
  --name ebs-csi-controller-sa \
  --namespace kube-system \
  --cluster devx-dev-cluster \
  --role-name AmazonEKS_EBS_CSI_DriverRole_v2 \
  --role-only \
  --attach-policy-arn arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy \
  --approve

# Step 7 — install EBS CSI driver addon
aws eks create-addon \
  --cluster-name devx-dev-cluster \
  --addon-name aws-ebs-csi-driver \
  --service-account-role-arn arn:aws:iam::443938285767:role/AmazonEKS_EBS_CSI_DriverRole_v2 \
  --region us-east-1

# Step 8 — patch StorageClass to default
kubectl patch storageclass gp2 \
  -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'

# Step 9 — deploy app via Helm
cd ~/devx-platform-engineering
helm install devx-app phase2-kubernetes/helm/fastapi-app \
  -f phase4-eks/03-helm/values-eks.yaml \
  -n devx \
  --create-namespace

# Step 10 — get LoadBalancer URL
kubectl get service fastapi-service -n devx
# wait for EXTERNAL-IP to populate (2-3 min)

# Step 11 — test endpoints
ELB=$(kubectl get svc fastapi-service -n devx -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
curl http://$ELB/health
curl http://$ELB/health/ready
curl http://$ELB/api/v1/items
```

---

## Destroy order (reverse — protect credits)

```bash
# 1. Remove Helm release
helm uninstall devx-app -n devx

# 2. Delete EBS CSI addon
aws eks delete-addon \
  --cluster-name devx-dev-cluster \
  --addon-name aws-ebs-csi-driver \
  --region us-east-1

# 3. Destroy EKS (15 min)
cd phase4-eks/02-eks && terraform destroy -auto-approve

# 4. Destroy ECR
cd ../01-ecr && terraform destroy -auto-approve

# 5. Destroy VPC
cd ../../phase3-terraform/01-vpc && terraform destroy -auto-approve

# 6. Keep 04-s3-backend (near zero cost, reuse for future)
```
