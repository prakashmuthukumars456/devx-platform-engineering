# Helm chart — fastapi-app

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
