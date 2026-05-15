# Phase 5.6 — Atlassian Rovo MCP Server: VS Code Integration

This sub-phase wires the **Atlassian Rovo MCP Server** into VS Code, enabling natural language queries and write operations against Jira and Confluence directly from the IDE — no browser context switching required.

The MCP (Model Context Protocol) server is a cloud-hosted bridge between your Atlassian workspace and any compatible AI client. Once connected, VS Code's agent chat can search issues, create tickets, summarize Confluence pages, and more — all via plain English prompts backed by your existing Atlassian permissions.

---

## Architecture

```
VS Code Agent Chat
       │
       ▼
.vscode/mcp.json  ──►  https://mcp.atlassian.com/v1/mcp/authv2
                                      │
                         OAuth 2.1 (browser consent)
                                      │
                    ┌─────────────────┼─────────────────┐
                    ▼                 ▼                  ▼
                  Jira           Confluence           Compass
               (DEVX project)  (DevX Platform)     (optional)
```

---

## Prerequisites

| Requirement | Version | Check |
|-------------|---------|-------|
| Node.js | v18+ | `node --version` |
| npx | any | `npx --version` |
| VS Code | latest | agent mode required |
| Atlassian account | active | `prakashmuthukumars456.atlassian.net` |

---

## Step 1 — Install Node.js v20

`nvm` is the recommended way to manage Node versions in WSL2.

```bash
# Install nvm
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash

# Reload shell to pick up nvm (re-reads ~/.bashrc without closing terminal)
source ~/.bashrc

# Install and activate Node 20
nvm install 20
nvm use 20

# Verify
node --version   # should print v20.x.x
npx --version
```

> **Why `source ~/.bashrc`?**
> The nvm install script appends its init lines to `~/.bashrc`. Your current terminal session loaded that file before those lines existed, so it doesn't know about `nvm` yet. `source ~/.bashrc` re-executes the file in the current session without needing to open a new terminal.

If `curl` is blocked, use the NodeSource apt fallback:

```bash
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt install -y nodejs
node --version
```

---

## Step 2 — Create the MCP config in the repo

The `mcp.json` file tells VS Code which MCP servers to connect to. Placing it in `.vscode/` scopes it to this workspace only.

```bash
cd ~/devx-platform-engineering
mkdir -p .vscode
cat > .vscode/mcp.json << 'EOF'
{
  "servers": {
    "atlassian-mcp-server": {
      "url": "https://mcp.atlassian.com/v1/mcp/authv2",
      "type": "http"
    }
  },
  "inputs": []
}
EOF
```

> **Endpoint note:** The legacy SSE endpoint (`/v1/sse`) is deprecated after June 2026. Always use `/v1/mcp/authv2` going forward.

---

## Step 3 — Authenticate via OAuth in VS Code

```bash
code .
```

Inside VS Code:

1. Press `Ctrl+Shift+P` → type **Chat: Open Chat** → Enter
2. In the chat panel, switch mode from **Ask** → **Agent** (dropdown at bottom of the chat input box)
3. Type any Atlassian-targeted prompt, for example:

```
Can you see my DEVX Jira project?
```

4. VS Code detects `.vscode/mcp.json` and opens an **OAuth browser popup** to `atlassian.com`
5. Log in with your `prakashmuthukumars456` Atlassian account
6. Review and **Accept** the requested scopes (Jira read/write, Confluence read/write)
7. Return to VS Code — the agent chat now has live Atlassian context

> **OAuth vs API token:** Use OAuth (the default browser flow). API tokens work for Jira REST calls but the Rovo MCP server requires OAuth 2.1 to verify workspace permissions correctly.

---

## Step 4 — Verify the connection

Test each prompt in the VS Code agent chat to confirm all three capabilities are working:

**Read — Query Jira issues:**
```
Show me all issues in the DEVX project
```

**Read — Summarise Confluence:**
```
Summarise the DevX Platform Confluence space
```

**Write — Create a Jira issue:**
```
Create a Jira issue in DEVX titled "Add readiness probe to EKS deployment"
```

Expected behaviour for each:
- Jira query returns a list of DEVX issues with status and assignee
- Confluence summary returns an overview of the DevX Platform space pages
- Issue creation returns a new ticket key (e.g. `DEVX-3`) and a link

---

## What this enables

Once connected, the full set of Rovo MCP tools is available in VS Code agent mode:

| Action | Example prompt |
|--------|---------------|
| Search Jira | `Find all Done issues in DEVX this week` |
| Create issue | `Create a DEVX bug: EKS pod restarts on high memory` |
| Update issue | `Move DEVX-2 to In Progress` |
| Search Confluence | `Find the latest runbook in DevX Platform space` |
| Create Confluence page | `Create a page in DevX Platform titled "Phase 5 MCP Setup"` |
| Cross-reference | `Link DEVX-3 to the Phase 5 Confluence page` |

---

## Project Phase Summary

| Phase | Focus | Status |
|-------|-------|--------|
| 1 — Docker | Multi-stage builds, Compose, health probes | ✅ Done |
| 2 — Kubernetes | Docker Desktop K8s, manifests, Helm | ✅ Done |
| 3 — Terraform | AWS VPC, EC2, S3 backend, RDS | ✅ Done |
| 4 — EKS | Terraform + EKS cluster, ECR, Helm on AWS | ✅ Done |
| 5 — Rovo Dev | Jira ↔ GitHub ↔ Confluence SDLC automation | ✅ Done |
| 5.6 — Rovo MCP | Atlassian MCP Server wired into VS Code agent | ✅ Done |

---

## Links

- Atlassian Rovo MCP docs: https://support.atlassian.com/atlassian-rovo-mcp-server/
- MCP Server GitHub: https://github.com/atlassian/atlassian-mcp-server
- Jira Project: https://prakashmuthukumars456.atlassian.net/jira/software/projects/DEVX/boards/34
- Confluence Space: https://prakashmuthukumars456.atlassian.net/wiki/spaces/DP/overview