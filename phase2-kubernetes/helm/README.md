# Helm chart — fastapi-app

<img width="717" height="247" alt="image" src="https://github.com/user-attachments/assets/f9761f3e-905d-434a-b3ca-238d00ce5f06" />

Helm wraps all manifests into one reusable chart.
Same chart deploys to dev, staging, and prod — only values differ.

## Structure

```
fastapi-app/
├── Chart.yaml            # chart name, version, appVersion
├── values.yaml           # defaults (used if no override provided)
├── values-dev.yaml       # dev overrides  (replicas=1, DEBUG=true)
├── values-prod.yaml      # prod overrides (replicas=3, real ECR image)
└── templates/
    ├── _helpers.tpl      # reusable named templates (labels, fullname)
    ├── namespace.yaml    # namespace: devx
    ├── configmap.yaml    # non-sensitive env vars  ← from values.config
    ├── secret.yaml       # passwords (auto base64) ← from values.secrets
    ├── postgres.yaml     # PVC + Deployment + Service
    ├── redis.yaml        # Deployment + Service
    └── app.yaml          # Deployment + Service
```

## Key concept

```
values.yaml          templates/app.yaml
────────────         ──────────────────
app:                 replicas: {{ .Values.app.replicas }}
  replicas: 2   →   image: {{ .Values.app.image.repository }}:{{ .Values.app.image.tag }}
  image: ...
```

Everything hardcoded in raw manifests is now a variable.

## Commands

```bash
# Install using default values
helm install devx-app ./fastapi-app -n devx --create-namespace

# Install with dev overrides
helm install devx-app ./fastapi-app -f values-dev.yaml

# Upgrade after changing values
helm upgrade devx-app ./fastapi-app -f values-dev.yaml

# Preview rendered YAML without deploying (most useful command)
helm template devx-app ./fastapi-app -f values-dev.yaml

# See what's deployed
helm list -n devx

# Check status
helm status devx-app -n devx

# Rollback to previous release
helm rollback devx-app 1 -n devx

# Uninstall everything
helm uninstall devx-app -n devx
```

## Before installing

Delete existing raw manifest deployment first (avoid conflicts):
```bash
kubectl delete namespace devx
```

Then install via Helm:
```bash
helm install devx-app ./fastapi-app -f values-dev.yaml
kubectl get pods -n devx -w
```

## The full hierarchy with your Helm setup

<img width="652" height="396" alt="image" src="https://github.com/user-attachments/assets/7cf16e9b-0f67-4b17-a486-97340bd2fe28" />

Cluster                         → the whole K8s environment
  └── Node (docker-desktop)     → the one machine
        └── Namespace (devx)    → logical isolation
              └── Helm release (devx-app)   → owns everything below
                    ├── Deployment: fastapi-app
                    │     ├── Pod 1 (replica 1)
                    │     │     └── Container: fastapi-k8s-app-app:latest
                    │     └── Pod 2 (replica 2)
                    │           └── Container: fastapi-k8s-app-app:latest
                    ├── Deployment: postgres
                    │     └── Pod → Container: postgres:16-alpine
                    ├── Deployment: redis
                    │     └── Pod → Container: redis:7-alpine
                    ├── ConfigMap: app-config
                    ├── Secret: app-secret
                    └── PVC: postgres-pvc

## Phase 2 vs Phase 4
<img width="645" height="518" alt="image" src="https://github.com/user-attachments/assets/00cec687-a1f8-41a5-8a4d-403900c2092d" />

## The full chain with all components
<img width="681" height="535" alt="image" src="https://github.com/user-attachments/assets/01bf89dd-78a1-415c-88ce-df9c3683e748" />
