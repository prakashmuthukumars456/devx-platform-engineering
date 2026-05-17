# Phase 7 — Autonomous SRE Remediation Loop

This phase builds a mini Bits AI SRE system — a fully automated incident detection and remediation pipeline that mirrors what Datadog's Bits AI SRE does in production.

When a container goes down, the system detects it, opens a GitHub issue, queries Datadog for logs and metrics, sends them to Claude for root cause analysis, restarts the container, verifies recovery, and closes the issue — all without human intervention.

---

## The Full Loop

```
docker stop devx-postgres          ← incident
        ↓
Datadog Agent detects NO DATA      ← observability
        ↓
Monitor fires → webhook            ← alerting
        ↓
GitHub repository_dispatch         ← event bridge
        ↓
Actions workflow triggers          ← automation
        ↓
GitHub Issue created (P1)          ← incident management
        ↓
sre_agent.py queries Datadog       ← diagnosis
        ↓
Claude generates RCA               ← AI analysis
        ↓
docker start devx-postgres         ← remediation
        ↓
Issue closed with RCA comment      ← resolution
```

---

## Architecture

### Component Map

| Component | Role | Where |
|-----------|------|-------|
| Docker containers | Target services being monitored | WSL2 Ubuntu 24.04 |
| Datadog Agent v7 | Collects metrics and logs from containers | Docker container (dd-agent) |
| Datadog Monitor (P1) | Watches `docker.containers.running{image_name:postgres}` | us5.datadoghq.com |
| Datadog Webhook | Fires HTTP POST to GitHub on alert | Webhooks integration |
| GitHub repository_dispatch | Event bridge between Datadog and Actions | GitHub API |
| GitHub Actions workflow | Orchestrates diagnosis and remediation | `.github/workflows/sre-remediation.yml` |
| Self-hosted runner | Executes workflow on local machine (accesses Docker) | WSL2, `devx-local` label |
| sre_agent.py | Queries Datadog REST API, calls Claude for RCA | `.github/scripts/sre_agent.py` |
| Claude API | Analyses logs and metrics, generates RCA | api.anthropic.com |
| GitHub Issues | Incident tracking with auto-created and auto-closed issues | devx-platform-engineering |

---

## Why a Self-Hosted Runner?

GitHub-hosted runners run in GitHub's cloud datacenters. They have no network access to your local Docker daemon. The self-hosted runner runs on your own machine, where Docker lives — so it can execute `docker start devx-postgres` directly.

```
GitHub-hosted runner (Azure DC) → ✗ cannot reach localhost:2375
Self-hosted runner (WSL2)       → ✓ direct Docker socket access
```

In production, the equivalent is a runner pod inside the same Kubernetes cluster, with a service account that can exec `kubectl rollout restart`.

---

## Setup

### Prerequisites

- Docker Desktop with WSL2 integration
- Datadog account (free trial — us5 region)
- GitHub repository with Actions enabled
- Anthropic API key

### Step 1 — Run the stack

```bash
cd devx-platform-engineering/phase1-docker
export DD_API_KEY=your_key_here
docker compose -f docker-compose.datadog.yml up -d
```

Verify all four containers are healthy:
```bash
docker compose -f docker-compose.datadog.yml ps
```

### Step 2 — Self-hosted runner

```bash
mkdir ~/actions-runner && cd ~/actions-runner
curl -o actions-runner-linux-x64.tar.gz -L \
  https://github.com/actions/runner/releases/download/v2.334.0/actions-runner-linux-x64-2.334.0.tar.gz
tar xzf ./actions-runner-linux-x64.tar.gz

./config.sh \
  --url https://github.com/YOUR_USERNAME/devx-platform-engineering \
  --token YOUR_RUNNER_TOKEN

./run.sh  # keep this terminal open
```

Verify at: `https://github.com/YOUR_USERNAME/devx-platform-engineering/settings/actions/runners`

### Step 3 — GitHub secrets

Add these at `Settings → Secrets → Actions`:

| Secret | Value |
|--------|-------|
| `DD_API_KEY` | Datadog API key |
| `DD_APP_KEY` | Datadog application key (`ddapp_...`) |
| `ANTHROPIC_API_KEY` | Anthropic API key (`sk-ant-...`) |

### Step 4 — Datadog webhook

Go to `Integrations → Webhooks → New`:

- **Name:** `github-sre`
- **URL:** `https://api.github.com/repos/YOUR_USERNAME/devx-platform-engineering/dispatches`
- **Payload:**

```json
{
  "event_type": "datadog-alert",
  "client_payload": {
    "monitor": "$EVENT_TITLE",
    "host": "$HOSTNAME",
    "alert_id": "$ALERT_ID",
    "alert_type": "$ALERT_TYPE",
    "container": "devx-postgres"
  }
}
```

- **Custom Headers:**

```json
{
  "Authorization": "Bearer YOUR_GITHUB_PAT",
  "Content-Type": "application/json"
}
```

GitHub PAT needs `repo` + `workflow` scopes.

### Step 5 — Datadog monitor

Go to `Monitors → New Monitor → Metric`:

- **Detection:** Threshold Alert
- **Metric:** `docker.containers.running` from `image_name:postgres`
- **Evaluate:** minimum over last 1 minute
- **Alert when:** below 1
- **If data missing:** Show NO DATA and notify
- **Priority:** P1
- **Message:**

```
{{#is_no_data}}
Postgres container devx-postgres is NOT REPORTING on {{host.name}}.
Triggering SRE auto-remediation via GitHub Actions.
@webhook-github-sre
{{/is_no_data}}

{{#is_alert}}
Postgres container devx-postgres is DOWN on {{host.name}}.
@webhook-github-sre
{{/is_alert}}

{{#is_recovery}}
Postgres container devx-postgres has RECOVERED.
@webhook-github-sre
{{/is_recovery}}
```

---

## Testing

### Manual trigger (fastest)

```bash
curl -X POST \
  -H "Authorization: Bearer YOUR_PAT" \
  -H "Accept: application/vnd.github.v3+json" \
  -H "Content-Type: application/json" \
  https://api.github.com/repos/YOUR_USERNAME/devx-platform-engineering/dispatches \
  -d '{
    "event_type": "datadog-alert",
    "client_payload": {
      "monitor": "DevX Postgres Container Down on docker-desktop",
      "host": "docker-desktop",
      "alert_id": "test-001",
      "alert_type": "ALERT",
      "container": "devx-postgres"
    }
  }'
```

### Full loop trigger (via Datadog)

```bash
# Start postgres so monitor goes OK
docker start devx-postgres

# Wait 2 minutes for monitor to settle
# Then stop it — Datadog fires the webhook automatically
docker stop devx-postgres
```

Watch:
- Monitor: `https://app.datadoghq.com/monitors`
- Actions: `https://github.com/YOUR_USERNAME/devx-platform-engineering/actions`
- Issues: `https://github.com/YOUR_USERNAME/devx-platform-engineering/issues`

---

## What Claude Receives and Returns

### Input to Claude

```
You are an SRE agent investigating a P1 incident.
Container DOWN: devx-postgres

Recent logs (last 15 minutes):
[2026-05-18T02:07:38] received fast shutdown request
[2026-05-18T02:07:38] aborting any active transactions
[2026-05-18T02:07:38] shutting down
[2026-05-18T02:07:38] database system is shut down

Container running metric (last 30 min):
[[1747527600, 1.0], [1747527900, 1.0], [1747528200, null]]

Provide a concise RCA with exactly 3 bullet points:
- Root cause
- Remediation
- Verification
```

### Claude's RCA output (posted to GitHub Issue)

```
- Root cause: Container received a fast shutdown request 
  (SIGTERM) at 02:07:38 UTC, triggering an orderly postgres 
  shutdown. No crash or OOM — clean stop.

- Remediation: Container restarted via docker start 
  devx-postgres by SRE agent at 02:09:15 UTC.

- Verification: Confirm pg_isready returns accepting 
  connections and devx-app /health returns 200 OK.
```

---

## Key Learnings

**Why NO DATA, not ALERT**
When a container stops, the Datadog agent stops emitting `docker.containers.running` for that container — it doesn't report `0`. The metric simply disappears. The monitor must be configured to treat missing data as an alert trigger (`Show NO DATA and notify`), not a threshold breach.

**Why the webhook payload must match GitHub's dispatches API**
GitHub's `/dispatches` endpoint expects exactly `{"event_type": "...", "client_payload": {...}}`. The Datadog webhook default template sends a completely different format — it must be replaced entirely.

**Why direct Datadog REST API, not MCP**
The Datadog MCP server is designed for interactive clients (VS Code, Cursor). For automated scripts, direct REST API calls to `api.us5.datadoghq.com` are simpler and more reliable. The same logs and metrics are available either way.

**The production equivalent**
In a production SRE setup, this same pattern runs with:
- Runner pod inside EKS with IAM role instead of local Docker socket
- `kubectl rollout restart` instead of `docker start`
- PagerDuty or Slack notification in addition to GitHub issue
- Datadog SLO tracking the MTTR

---

## Project Phase Summary

| Phase | Focus | Status |
|-------|-------|--------|
| 1 — Docker | Multi-stage builds, Compose, health probes | ✅ Done |
| 2 — Kubernetes | Docker Desktop K8s, manifests, Helm | ✅ Done |
| 3 — Terraform | AWS VPC, EC2, S3 backend, RDS | ✅ Done |
| 4 — EKS | Terraform + EKS cluster, ECR, Helm on AWS | ✅ Done |
| 5 — Rovo Dev | Jira ↔ GitHub ↔ Confluence SDLC automation | ✅ Done |
| 5.6 — Rovo MCP | Atlassian MCP Server in VS Code | ✅ Done |
| 6 — Datadog MCP | Datadog agent + MCP Server + VS Code agent | ✅ Done |
| 7 — SRE Remediation | Autonomous incident detection + Claude RCA + auto-fix | ✅ Done |

---

## Links

- Datadog Monitor: https://app.datadoghq.com/monitors
- Datadog Logs: https://app.datadoghq.com/logs/livetail
- GitHub Actions: https://github.com/prakashmuthukumars456/devx-platform-engineering/actions
- GitHub Issues: https://github.com/prakashmuthukumars456/devx-platform-engineering/issues
- Jira Project: https://prakashmuthukumars456.atlassian.net/jira/software/projects/DEVX/boards/34
- Confluence Space: https://prakashmuthukumars456.atlassian.net/wiki/spaces/DP/overview
