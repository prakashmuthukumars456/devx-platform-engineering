# Phase 4 — EKS Deep Dive

Companion to `PHASE4_FILE_REFERENCE.md`. This covers concepts, command reference, and architecture flows. Save in your repo as `phase4-eks/DEEP_DIVE.md`.

---

## Table of contents

1. [Commands by category](#1-commands-by-category)
2. [IRSA + OIDC](#2-irsa--oidc)
3. [EBS CSI architecture](#3-ebs-csi-architecture)
4. [Full request flow](#4-full-request-flow)
5. [Production patterns demonstrated](#5-production-patterns-demonstrated)
6. [Whats missing for production](#6-whats-missing-for-production)

---

## 1. Commands by category

Every command used in Phase 4, grouped by tool. Each command is annotated with what it actually does.

### Terraform — infrastructure

Provisions VPC, ECR, EKS, IAM roles via `.tf` files. State stored in S3 for team sharing. `-auto-approve` skips the yes prompt — use carefully in production.

```bash
terraform init                  # download provider plugins
terraform init -migrate-state   # move local state to S3
terraform plan                  # preview changes, no apply
terraform apply -auto-approve   # create AWS resources
terraform output                # show export values
terraform destroy -auto-approve # delete everything
```

**Creates in AWS:** IAM, VPC, EKS, ECR, S3, DynamoDB

---

### AWS CLI — addons and auth

Direct AWS API calls. EKS addons are managed separately from Terraform because they include IRSA service account bindings that don't map cleanly to Terraform resources.

```bash
aws sts get-caller-identity                  # confirm AWS auth
aws eks update-kubeconfig --name <cluster>   # connect kubectl
aws eks create-addon                         # install EBS CSI driver
aws eks describe-addon --query addon.status  # check addon health
aws ecr get-login-password | docker login    # auth docker with ECR
```

**Used for:** EKS addons, ECR authentication

---

### eksctl — IRSA setup

High-level EKS tool. Used specifically for IRSA setup because OIDC provider creation + IRSA role binding requires many AWS API calls done in the right order — eksctl handles this in one command.

```bash
eksctl utils associate-iam-oidc-provider \
  --region us-east-1 \
  --cluster devx-dev-cluster \
  --approve

eksctl create iamserviceaccount \
  --name ebs-csi-controller-sa \
  --namespace kube-system \
  --role-only \
  --attach-policy-arn <ebs-csi-policy>
```

**Creates in AWS:** OIDC provider, IAM role with IRSA trust policy

---

### Docker — build and push

Build runs on your laptop. Tag adds the destination address. Push uploads to ECR. EKS nodes then pull from ECR using their IAM role permission.

```bash
docker build -t devx-dev-app .                          # build locally
docker tag devx-dev-app:latest <ecr-url>:latest         # tag for ECR
docker push <ecr-url>:latest                            # upload to ECR
docker compose ps                                       # check containers
```

**Result:** Image stored in ECR, accessible to EKS

---

### kubectl — cluster operations

Talks to the EKS API server. After `update-kubeconfig`, every kubectl runs against your AWS cluster instead of Docker Desktop.

```bash
kubectl get nodes                              # show worker nodes
kubectl get pods -n devx -w                    # watch pods
kubectl get pods -n kube-system | grep ebs     # check addon pods
kubectl get service fastapi-service -n devx    # get ELB URL
kubectl logs -n devx <pod-name> --tail=30      # check logs
kubectl describe pod -n devx <pod-name>        # see events
kubectl delete pod -n devx -l app=postgres     # force restart
kubectl rollout restart deployment/<name> -n devx
```

**Visible:** Pods, services, events, logs

---

### Helm — application deployment

Same chart from Phase 2. Only the values file differs. `-f` flag merges `values-eks.yaml` over defaults. `helm upgrade` applies changes.

```bash
helm install devx-app phase2-kubernetes/helm/fastapi-app \
  -f phase4-eks/03-helm/values-eks.yaml \
  -n devx \
  --create-namespace

helm upgrade devx-app <chart> -f values-eks.yaml -n devx
helm list -n devx
helm status devx-app -n devx
helm uninstall devx-app -n devx
```

**Creates in cluster:** Deployment, Service, ConfigMap, Secret, PVC

---

## 2. IRSA + OIDC

### What problem does IRSA solve?

Pods need AWS credentials but they aren't EC2 instances. Without IRSA, every pod on a node inherits the node's IAM role — your fastapi pod could create EBS volumes too. That's a security disaster.

```
Pod: ebs-csi-controller
  needs: create EBS volumes (yes)

Pod: fastapi-app
  needs: nothing AWS (correct)

With node IAM only: both get same permissions  WRONG
With IRSA: each pod gets exactly what it needs  RIGHT
```

---

### OIDC — the trust mechanism

OIDC = OpenID Connect. When a pod tries to assume an IAM role, AWS needs proof the pod is who it claims. OIDC provides that proof via signed JWT tokens issued by the cluster.

```
1. Pod has K8s service account
2. K8s issues signed JWT token to pod
3. Pod presents token to AWS STS
4. AWS checks token against clusters OIDC provider
5. AWS verifies trust policy on IAM role
6. AWS issues temporary credentials
7. Pod uses creds to call AWS APIs
```

---

### IRSA — IAM Roles for Service Accounts

Links a K8s service account to an AWS IAM role. The role's trust policy specifies which service account can assume it via OIDC.

**K8s side:**
```yaml
ServiceAccount: ebs-csi-controller-sa
  annotation: eks.amazonaws.com/role-arn = <role-arn>
```

**AWS side:**
```
IAM Role: AmazonEKS_EBS_CSI_DriverRole_v2
  trust policy:
    OIDC provider: <cluster-oidc-url>
    condition: sub = system:serviceaccount:kube-system:ebs-csi-controller-sa
  attached policy: AmazonEBSCSIDriverPolicy
```

---

### Why we hit this issue

EKS 1.32 EBS CSI driver requires IRSA. Without OIDC provider configured, the controller pods got no credentials and crashed with `no EC2 IMDS role found`. Setting up OIDC + IRSA was the only fix.

The diagnostic output that revealed the issue:
```
E0511 15:32:30  csi-provisioner.go:242
CSI driver probe failed: rpc error
Failed health check (verify network connection and IAM credentials):
dry-run EC2 API call failed:
no EC2 IMDS role found  -- this is the IRSA hint
```

---

### Analogy

```
Pod              =  employee at a company
Service Account  =  employees badge
IAM Role         =  list of doors they can open
OIDC Provider    =  the security system that verifies badges
```

Without OIDC — the security system isn't installed, badges don't work, doors stay locked. That's why the EBS controller couldn't create volumes.

---

## 3. EBS CSI architecture

### The components

EBS CSI driver has 2 deployments running in `kube-system`:
- **Controller** (Deployment) — creates and deletes EBS volumes. Needs IRSA for AWS API access.
- **Node** (DaemonSet) — mounts volumes inside pods. Uses node IAM role.

```
kubectl get pods -n kube-system | grep ebs

ebs-csi-controller-xxx   6/6   Running   creates volumes (needs IRSA)
ebs-csi-controller-yyy   6/6   Running
ebs-csi-node-zzz         3/3   Running   mounts on each node
ebs-csi-node-aaa         3/3   Running
```

---

### The volume lifecycle

```
1. PVC created (Pending)
2. StorageClass triggers EBS CSI provisioner
3. Controller calls AWS: CreateVolume
4. EBS volume created (vol-xxxxx, 1GiB gp2)
5. PVC binds to volume (Bound)
6. Pod scheduled to node
7. EBS CSI node attaches + mounts to pod
8. Postgres writes to /var/lib/postgresql/data/pgdata
```

Visible in AWS console under EC2 -> Volumes.

---

### The PGDATA subdirectory fix

EBS volumes auto-create `lost+found` at the root. Postgres `initdb` refuses non-empty data directories. Setting `PGDATA` to a subdirectory bypasses this.

**Before — broken:**
```
/var/lib/postgresql/data/
+-- lost+found/         <- breaks initdb
+-- (would init here)
```

**After — works:**
```
/var/lib/postgresql/data/
+-- lost+found/         <- ignored
+-- pgdata/             <- postgres data here OK
    +-- PG_VERSION, etc
```

The fix in Helm template:
```yaml
env:
  - name: PGDATA
    value: /var/lib/postgresql/data/pgdata
```

---

## 4. Full request flow

### The complete path

When you curl the ELB URL, the request travels through 6 AWS components before reaching postgres. This is the production traffic pattern you'll see in any cloud-native app.

```
1. curl http://<elb-url>/api/v1/items
   v
2. AWS Route 53 resolves ELB DNS
   v
3. AWS Elastic Load Balancer
   distributes to healthy fastapi pods
   v
4. EKS node (EC2) kube-proxy routes to pod IP
   v
5. fastapi pod (your container)
   reads POSTGRES_HOST = postgres-service
   v
6. K8s service: postgres-service
   resolves to postgres pod IP via CoreDNS
   v
7. postgres pod reads from EBS volume
   v
8. response travels back the same path
```

---

### Cost breakdown per hour

| Resource | Cost | Notes |
|---|---|---|
| EKS control plane | $0.10/hr | Fixed cost regardless of usage |
| 2x t3.small nodes | $0.046/hr | Worker capacity |
| EBS volume 1GiB gp2 | ~$0/hr | Within free tier |
| ELB (network) | ~$0.025/hr | Per load balancer |
| ECR storage | ~$0/hr | < 1GB free |
| CloudWatch logs | ~$0/hr | 5GB free |
| **Total** | **~$0.17/hr** | |

With $119 credit: ~700 hours runtime — plenty for learning.

---

## 5. Production patterns demonstrated

Real production concepts you actually implemented. These are interview gold — concrete examples beat textbook answers every time.

- Infrastructure as Code — Terraform modules with explicit dependencies
- Remote state with locking — S3 backend + DynamoDB
- Container registry per environment — ECR with lifecycle policy
- Multi-stage Docker builds — smaller image size, no compiler in runtime
- K8s health probes — separate liveness vs readiness
- Helm chart with environment overrides — same chart, different values files
- IAM least-privilege via IRSA — pod-level identity, not node-level
- Private database isolation — postgres in private subnet (Phase 3)
- Production debug toggle — DEBUG=false hides Swagger in prod
- Persistent volumes via CSI driver — EBS CSI managed lifecycle
- Self-healing reconciliation — K8s controllers maintain desired state
- Rolling deployments — maxUnavailable: 1 keeps service available
- Auto-scaling node groups — min/max for cluster autoscaler
- CloudWatch observability — Container Insights integration

---

## 6. Whats missing for production

Honest gaps in this learning project. Acknowledging these shows maturity in interviews — you know what's left to do.

```
- HTTPS/TLS                  -> need ACM certificate + ALB Ingress Controller
- Domain name                -> need Route 53 hosted zone
- Secrets management         -> move from Helm values to AWS Secrets Manager
- Multi-AZ RDS               -> replace in-cluster postgres
- Backup strategy            -> automated EBS snapshots
- Network policies           -> restrict pod-to-pod communication
- Pod security standards     -> restrict container privileges
- HorizontalPodAutoscaler    -> scale pods on CPU/memory
- Cluster Autoscaler         -> scale nodes on pod demand
- GitOps                     -> ArgoCD or Flux for Git-driven deploys
- Richer metrics             -> Prometheus + Grafana stack
- Distributed tracing        -> Jaeger or AWS X-Ray
```

Each item maps to a real production task you'd own as a DevX/SRE engineer. When an interviewer asks "what would you add to this?" — you have 12 concrete answers.

---

## Quick reference card

The 5 most important commands to remember:

```bash
# 1. Connect kubectl to EKS
aws eks update-kubeconfig --region us-east-1 --name devx-dev-cluster

# 2. Set up IRSA for a service account
eksctl create iamserviceaccount \
  --name <sa-name> \
  --namespace <ns> \
  --cluster <cluster-name> \
  --attach-policy-arn <policy> \
  --approve

# 3. Deploy app via Helm
helm install <release> <chart-path> -f <values-file> -n <ns> --create-namespace

# 4. Debug a failing pod
kubectl describe pod -n <ns> <pod-name>    # events first
kubectl logs -n <ns> <pod-name> --tail=30  # logs second

# 5. Destroy everything safely
helm uninstall <release> -n <ns>
terraform destroy -auto-approve   # in reverse module order
```

Memorise these — they handle 80% of EKS operations.
