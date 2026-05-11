# Phase 4 — EKS with Terraform

Deploy the FastAPI app to a real AWS EKS cluster.
Combines everything from Phases 1-3:
- Docker image pushed to ECR (not local)
- Kubernetes running on AWS (not Docker Desktop)
- Helm deploys the app (same chart, new values-eks.yaml)
- Terraform provisions the entire cluster
- CloudWatch replaces local observability

## Folder structure

```
phase4-eks/
├── 01-ecr/           # ECR private registry for Docker images
├── 02-eks/           # EKS cluster + IAM roles + node group
├── 03-helm/          # values-eks.yaml for EKS deployment
└── 04-observability/ # CloudWatch Container Insights + alarms
```

## What changes from Phase 2 (Docker Desktop K8s)

| Phase 2 | Phase 4 |
|---|---|
| Local Docker image | Image in ECR |
| Docker Desktop K8s | AWS EKS cluster |
| imagePullPolicy: Never | imagePullPolicy: Always |
| LoadBalancer = localhost | LoadBalancer = AWS ELB |
| No IAM | IAM roles for nodes |
| No observability | CloudWatch Container Insights |

## Cost per session

| Resource | Cost |
|---|---|
| EKS control plane | $0.10/hr |
| 2x t3.small nodes | $0.046/hr |
| ECR storage | ~$0/mo |
| CloudWatch logs | ~$0.01/day |
| **Total** | **~$0.15/hr** |

Always `terraform destroy` after each session.

## Deploy order

```bash
# Step 1 — VPC (reuse Phase 3 or recreate)
cd phase3-terraform/01-vpc && terraform init && terraform apply

# Step 2 — ECR (create registry)
cd phase4-eks/01-ecr && terraform init && terraform apply
terraform output docker_login_cmd   # save this

# Step 3 — Build and push Docker image to ECR
cd phase1-docker
$(terraform -chdir=../phase4-eks/01-ecr output -raw docker_login_cmd)
docker build -t devx-dev-app .
docker tag devx-dev-app:latest <ecr_url>:latest
docker push <ecr_url>:latest

# Step 4 — Create EKS cluster (takes 15-20 min)
cd phase4-eks/02-eks && terraform init && terraform apply

# Step 5 — Connect kubectl to EKS
$(terraform output -raw kubeconfig_cmd)
kubectl get nodes   # should show 2 nodes Ready

# Step 6 — Deploy via Helm
cd phase4-eks/03-helm
helm install devx-app ../../phase2-kubernetes/helm/fastapi-app \
  -f values-eks.yaml \
  -n devx \
  --create-namespace

# Step 7 — Get LoadBalancer URL
kubectl get service fastapi-service -n devx
# EXTERNAL-IP column shows your AWS ELB URL

# Step 8 — Enable observability
cd phase4-eks/04-observability && terraform init && terraform apply
```

## Test endpoints

```bash
# Get the ELB URL
ELB=$(kubectl get svc fastapi-service -n devx -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

curl http://$ELB/health
curl http://$ELB/health/ready
curl http://$ELB/api/v1/items
```

## Useful commands

```bash
# Check cluster
kubectl get nodes
kubectl get pods -n devx
kubectl get services -n devx

# Check logs
kubectl logs -n devx deployment/fastapi-app

# Check Helm release
helm list -n devx
helm status devx-app -n devx

# Update image after code change
docker build -t <ecr_url>:v2 .
docker push <ecr_url>:v2
helm upgrade devx-app ./fastapi-app -f values-eks.yaml \
  --set app.image.tag=v2 -n devx
```

## Destroy order

```bash
# Remove Helm release first
helm uninstall devx-app -n devx

# Then Terraform in reverse
cd 04-observability && terraform destroy -auto-approve
cd ../02-eks        && terraform destroy -auto-approve  # takes 15 min
cd ../01-ecr        && terraform destroy -auto-approve
cd ../../phase3-terraform/01-vpc && terraform destroy -auto-approve
```
