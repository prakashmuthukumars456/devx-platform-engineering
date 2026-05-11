# DevX Platform Engineering — Troubleshooting Log

> Real bugs hit during deployment. Each entry documents the problem, root cause, and fix.
> This is the kind of debugging engineers face daily — production-grade DevX work.

---

## Phase 1 — Docker

### 1. Container nesting causing flat file structure on first download
**Symptom:** All app files dumped flat in folder instead of inside `app/` subfolder.
**Root cause:** Downloaded files arrived without preserved folder structure.
**Fix:** Manually created `app/`, `app/core/`, `app/models/`, `app/routers/` and moved files using `mkdir -p` + `mv` commands.

### 2. Dockerfile COPY failing: "/app not found"
**Symptom:**
```
ERROR [final 6/6] COPY --chown=appuser:appgroup ./app ./app
"/app": not found
```
**Root cause:** `app/` subfolder didn't exist in build context — files were flat.
**Fix:** Recreated proper folder hierarchy before running `docker compose up --build`.

### 3. Postgres connection from psql shell - typing commands wrong
**Symptom:** Typing words like `localhost`, `appdb` at the `appdb=#` prompt.
**Root cause:** psql expects SQL commands, not configuration strings.
**Fix:** Use SQL syntax: `\dt`, `SELECT * FROM items;`, `\q` to exit.

---

## Phase 2 — Kubernetes on Docker Desktop

### 4. WSL2 trying to use Windows kubectl config
**Symptom:**
```
Error: Get "https://127.0.0.1:62649/api?timeout=32s": connection refused
```
**Root cause:** Docker Desktop writes kubeconfig to Windows side, WSL2 can't see it.
**Fix:**
```bash
mkdir -p ~/.kube
cp /mnt/c/Users/Prakash.M/.kube/config ~/.kube/config
kubectl config use-context docker-desktop
```

### 5. LoadBalancer EXTERNAL-IP stays `<pending>` on Docker Desktop
**Symptom:** Service shows `<pending>` for external IP.
**Root cause:** Local K8s can't provision real load balancers.
**Fix:** Use NodePort or `kubectl port-forward` to access services locally.

### 6. Helm install fails: namespace conflict
**Symptom:**
```
Error: namespaces "devx" already exists
```
**Root cause:** Chart's `templates/namespace.yaml` and `--create-namespace` flag both try to create the namespace.
**Fix:**
```bash
rm phase2-kubernetes/helm/fastapi-app/templates/namespace.yaml
# Let --create-namespace own namespace creation
```

### 7. Helm release in wrong namespace
**Symptom:** `helm list -n devx` returns empty after install.
**Root cause:** Forgot `-n devx` flag, installed to `default` namespace.
**Fix:** Always specify `-n devx` in all helm commands. Use `--create-namespace` once.

### 8. Cannot re-use release name
**Symptom:**
```
Error: cannot re-use a name that is still in use
```
**Root cause:** Old install lingering in different namespace.
**Fix:**
```bash
helm uninstall devx-app          # without -n, hits default
helm uninstall devx-app -n devx  # then with -n
kubectl delete namespace devx    # full clean slate
```

---

## Phase 3 — Terraform

### 9. Terraform: invalid character on single-line variable blocks
**Symptom:**
```
Error: Invalid character
variable "aws_region"  { type = string; default = "us-east-1" }
The ";" character is not valid.
```
**Root cause:** Terraform doesn't allow semicolons.
**Fix:** Multi-line block:
```hcl
variable "aws_region" {
  type    = string
  default = "us-east-1"
}
```

### 10. AWS rejects em dash in resource descriptions
**Symptom:**
```
InvalidParameterValue: ... must not contain non-printable control characters.
Character sets beyond ASCII are not supported.
```
**Root cause:** Em dash (`—`) in description fields.
**Fix:** Replace with regular hyphen (`-`) in all description attributes.

### 11. PowerShell paths leaking into WSL2 commands
**Symptom:**
```
cp -r ~/fastapi-k8s-app ./fastapi-k8s-app
Copy-Item: Cannot find path 'C:\Users\Prakash.M\fastapi-k8s-app'
```
**Root cause:** Running commands in PowerShell terminal instead of WSL2 bash.
**Fix:** Always check prompt — `PS C:\...` means PowerShell, `silk@LT-IND-...$` means WSL2. Use `wsl` command to switch.

### 12. GitHub password authentication deprecated
**Symptom:**
```
Password for 'https://prakashmuthukumars456@github.com':
remote: Support for password authentication was removed
```
**Root cause:** GitHub removed password auth in 2021.
**Fix:** Use Personal Access Token (Fine-grained) with `Contents: Read/Write` permission.

### 13. Git submodule confusion when nesting repos
**Symptom:**
```
hint: git submodule add <url> fastapi-k8s-app
create mode 160000 fastapi-k8s-app
```
**Root cause:** Inner folder had its own `.git` directory.
**Fix:**
```bash
rm -rf phase1-docker/.git    # remove nested git
git rm --cached fastapi-k8s-app   # remove from index
git add phase1-docker/
```

### 14. SSH connection refused on EC2 after first apply
**Symptom:**
```
ec2-user@x.x.x.x: Permission denied (publickey)
```
**Root cause:** Key file name mismatch — used `devxkey` instead of `devx-key`.
**Fix:** Match exact file name in SSH command. Verify with `ls ~/.ssh/`.

### 15. EC2 root volume too small (2GB default)
**Symptom:**
```
failed to register layer: no space left on device
```
**Root cause:** Amazon Linux 2023 default is 2GB. Docker needs ~10GB minimum.
**Fix:**
1. Console → EC2 → Volume → Modify → 20GB
2. On EC2: `sudo growpart /dev/nvme0n1 1 && sudo xfs_growfs /`
3. Add to Terraform: `root_block_device { volume_size = 20, volume_type = "gp3" }`

### 16. Buildx version too old on EC2
**Symptom:**
```
compose build requires buildx 0.17.0 or later
```
**Root cause:** Amazon Linux 2023 ships old buildx.
**Fix:**
```bash
mkdir -p ~/.docker/cli-plugins
curl -L https://github.com/docker/buildx/releases/download/v0.17.0/buildx-v0.17.0.linux-amd64 \
  -o ~/.docker/cli-plugins/docker-buildx
chmod +x ~/.docker/cli-plugins/docker-buildx
```

### 17. docker-compose environment overriding .env
**Symptom:** App connecting to local postgres container despite RDS endpoint in `.env`.
**Root cause:** `docker-compose.yml` has explicit `environment:` block that wins over `.env`.
**Fix:**
```bash
sed -i 's/POSTGRES_HOST: postgres/POSTGRES_HOST: <rds-endpoint>/' docker-compose.yml
```

---

## Phase 4 — EKS

### 18. Terraform output mismatch between modules
**Symptom:**
```
Error: Reference to undeclared resource "aws_eks_cluster" "main"
```
**Root cause:** Copy-paste error — `01-ecr/outputs.tf` had EKS outputs that belong in `02-eks`.
**Fix:** Each module's `outputs.tf` must only reference its own resources.

### 19. Remote state not found
**Symptom:**
```
Error: Unable to find remote state
No stored state was found for the given workspace
```
**Root cause:** Phase 3 VPC state was local, but Phase 4 EKS module tried to read it from S3.
**Fix:** Add S3 backend block to `01-vpc/main.tf` then `terraform init -migrate-state` to move local state to S3.

### 20. EKS node group fails: unsupported Kubernetes version
**Symptom:**
```
InvalidParameterException: Requested AMI for this version 1.29 is not supported
```
**Root cause:** AWS deprecated old K8s versions. 1.29 no longer has AMIs.
**Fix:** Upgrade to 1.32 in `terraform.tfvars`. Cannot skip versions, so destroy and recreate cluster fresh.

### 21. Docker not available in WSL2 terminal
**Symptom:**
```
The command 'docker' could not be found in this WSL 2 distro
```
**Root cause:** Docker Desktop WSL integration not enabled.
**Fix:** Docker Desktop → Settings → Resources → WSL Integration → Enable Ubuntu-24.04 → Apply & Restart.

### 22. EKS pods stuck in Pending — no StorageClass set
**Symptom:**
```
FailedScheduling: pod has unbound immediate PersistentVolumeClaims
no persistent volumes available for this claim and no storage class is set
```
**Root cause:** PVC didn't specify StorageClass, no default existed.
**Fix:**
```bash
kubectl patch storageclass gp2 \
  -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
```

### 23. EBS CSI driver controller in CrashLoopBackOff
**Symptom:**
```
1/6 CrashLoopBackOff
failed to refresh cached credentials, no EC2 IMDS role found
CSI driver probe failed: rpc error: dry-run EC2 API call failed
```
**Root cause:** EBS CSI controller pod needs AWS credentials. Node IAM role isn't enough — modern EBS CSI driver requires IRSA (IAM Roles for Service Accounts).
**Fix:**
```bash
# 1. Associate OIDC provider with cluster
eksctl utils associate-iam-oidc-provider \
  --region us-east-1 \
  --cluster devx-dev-cluster \
  --approve

# 2. Create IRSA role
eksctl create iamserviceaccount \
  --name ebs-csi-controller-sa \
  --namespace kube-system \
  --cluster devx-dev-cluster \
  --role-name AmazonEKS_EBS_CSI_DriverRole_v2 \
  --role-only \
  --attach-policy-arn arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy \
  --approve

# 3. Recreate addon with IRSA role
aws eks delete-addon --cluster-name devx-dev-cluster --addon-name aws-ebs-csi-driver --region us-east-1
sleep 30
aws eks create-addon \
  --cluster-name devx-dev-cluster \
  --addon-name aws-ebs-csi-driver \
  --service-account-role-arn arn:aws:iam::443938285767:role/AmazonEKS_EBS_CSI_DriverRole_v2 \
  --region us-east-1
```
**Key insight:** This is THE critical concept that separates beginner from senior EKS knowledge. IRSA = pod identity. OIDC = the trust mechanism that makes IRSA work.

### 24. Postgres fails to initialise on EBS volume
**Symptom:**
```
initdb: error: directory "/var/lib/postgresql/data" exists but is not empty
It contains a lost+found directory, perhaps due to it being a mount point.
```
**Root cause:** EBS volumes auto-create `lost+found` directory. Postgres `initdb` rejects non-empty data directories.
**Fix:** Set `PGDATA` env var to a subdirectory:
```yaml
env:
  - name: PGDATA
    value: /var/lib/postgresql/data/pgdata
```

### 25. FastAPI stuck in CrashLoopBackOff after postgres healthy
**Symptom:**
```
socket.gaierror: [Errno -2] Name or service not known
```
**Root cause:** `values-eks.yaml` had stale RDS endpoint as `POSTGRES_HOST` (from earlier draft). RDS was destroyed in Phase 3 cleanup — DNS resolution fails.
**Fix:**
```bash
sed -i 's|POSTGRES_HOST: "<old-rds-endpoint>"|POSTGRES_HOST: "postgres-service"|' \
  phase4-eks/03-helm/values-eks.yaml
helm upgrade devx-app phase2-kubernetes/helm/fastapi-app -f phase4-eks/03-helm/values-eks.yaml -n devx
```

### 26. Swagger /docs returns 404 in production
**Symptom:** All endpoints work, `/docs` returns 404.
**Root cause:** Intentional — `main.py` hides docs when `DEBUG=false`. This is correct production behaviour.
**Fix (only if you want to show docs):** Set `DEBUG: "true"` in `values-eks.yaml`.

---

## Patterns that emerged across phases

### Pattern 1 — Path / environment confusion
Multiple bugs from Windows path syntax in WSL2 commands. Always verify:
```bash
pwd                  # confirm correct directory
echo $0              # confirm shell (bash vs powershell)
```

### Pattern 2 — Stale state vs actual reality
Helm releases tracked old configs. Docker images cached old layers. K8s pods kept old DNS values. **Always restart deployments after config changes:**
```bash
kubectl rollout restart deployment/<name> -n <namespace>
```

### Pattern 3 — Layered configuration overrides
docker-compose env over .env, helm values-eks.yaml over values.yaml, K8s ConfigMap over container default. **Always trace the actual value being used:**
```bash
kubectl exec -n devx <pod> -- env | grep <KEY>
docker compose exec app env | grep <KEY>
```

### Pattern 4 — IAM in AWS is invisible until it isn't
Most Phase 4 hours were spent on IAM/IRSA/OIDC issues. In AWS, **silent failures usually mean missing permissions**. Always check IAM role policies before assuming code is broken.

---

## Lessons for production work

1. **Always destroy after each learning session** — EKS at $0.10/hr accumulates fast
2. **Document fixes immediately** — half this log was written from terminal scrollback
3. **Read pod events first** — `kubectl describe pod` solves 80% of K8s issues
4. **Read pod logs second** — `kubectl logs` solves the other 20%
5. **Check IAM third** — silent failures in AWS are usually permission denials
6. **Restart pods after config changes** — Helm upgrade doesn't always trigger restarts
7. **Use IRSA, not node IAM, for pod permissions** — node IAM is a security anti-pattern in production
