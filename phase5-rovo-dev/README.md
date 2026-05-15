# Phase 5 — Rovo Dev: Jira SDLC Automation

This phase wires the full SDLC loop using **Atlassian Rovo Dev**, **Jira**, **Confluence**, and the **GitHub** repository built across Phases 1–4. A Jira ticket creation triggers a branch, a commit links back to the ticket, a PR merge auto-transitions the ticket to Done, and a Confluence release note is auto-generated — all without manual intervention.

---

## Stack

| Tool | Role |
|------|------|
| Jira (DEVX project) | Issue tracking and workflow |
| Confluence (DevX Platform space) | Auto-generated release documentation |
| GitHub (`devx-platform-engineering`) | Source of truth for code changes |
| Rovo Dev (Atlassian AI) | Automation rule generation via natural language |
| Jira Automation | Rule engine executing the SDLC triggers |

---

## SDLC Loop — Step by Step

### Step 1 — Connect GitHub to Atlassian

GitHub organisation `prakashmuthukumars456` connected to Atlassian with Full Access across all repositories. Historical data backfilled from 16/11/2025.

![GitHub Connected to Atlassian](docs/screenshots/image1.png)

---

### Step 2 — GitHub Configuration — Connected Repositories

All 4 repositories visible in Jira under GitHub Cloud. Backfill status: **Finished**. Permissions: **Full Access**.

![GitHub Configuration in Jira](docs/screenshots/image2.png)

---

### Step 3 — Rovo Generates Automation Rule via Natural Language

Using the **Create with Rovo** prompt in Jira Automation, the following instruction was given:

> *"When a pull request is merged in GitHub and the branch name contains a DEVX issue key, transition that Jira issue to Done"*

Rovo generated the complete automation flow from this description.

![Rovo Automation Prompt](docs/screenshots/image4.png)

---

### Step 4 — Rule 1: PR Merged → Transition to Done (AI-Generated)

Rovo produced a 3-step automation rule:
- **Trigger:** Pull request merged
- **Condition:** `{{pullRequest.sourceBranch}}` contains regex `DEVX-\d+`
- **Action:** Transition the work item to `DONE`

No manual rule building required — Rovo inferred the trigger, condition, and action from the plain English prompt.

![Rule 1 — PR Merged to Done](docs/screenshots/image3.png)

---

### Step 5 — PR Raised on GitHub for DEVX-1

Branch `feature/DEVX-1-liveness-probe` pushed with commit message `DEVX-1: add liveness probe annotation to helm values`. PR raised with description `Closes DEVX-1`, targeting `main`.

![GitHub PR for DEVX-1](docs/screenshots/image5.png)

---

### Step 6 — DEVX-1 Ticket Transitions to Done Automatically

After the PR was merged, Rule 1 fired within seconds. The DEVX board shows `DEVX-1` moved to the **Done** column automatically — no manual status update.

![DEVX Board — Ticket in Done](docs/screenshots/image6.png)

---

### Step 7 — DEVX-1 Ticket Detail — Done + Development Panel

The ticket status shows **Done** with the Development panel reflecting `1 commit` linked 32 minutes ago. The full audit trail — branch, commit, PR — is visible inside the Jira ticket.

![DEVX-1 Ticket Done with Dev Panel](docs/screenshots/image8.png)

---

### Step 8 — Confluence Page Auto-Created by Rule 2

Rule 2 (Issue transitioned to Done → Create Confluence page) fired and published a new page titled **DEVX-1 - Add liveness probe to EKS deployment** in the DevX Platform space, containing Issue Description and Linked Pull Requests sections.

![Confluence Page Auto-Created](docs/screenshots/image7.png)

---

### Step 9 — Audit Log Shows SUCCESS

The Jira Automation audit log confirms Rule 2 executed successfully at `05/15/2026, 18:23:48` in **1.10s**, scoped to the **DEVX** project.

![Audit Log — SUCCESS](docs/screenshots/image9.png)

---

## Automation Rules Summary

| Rule | Trigger | Condition | Action |
|------|---------|-----------|--------|
| PR Merged → Done | Pull request merged | Branch name matches `DEVX-\d+` | Transition issue to Done |
| Done → Confluence | Issue transitioned to Done | Project = DEVX | Publish page in DevX Platform space |

Both rules were created using **Rovo Dev's natural language automation builder** — no manual flow configuration.

---

## Smart Commit Convention

All commits in this project follow the Jira smart commit format to auto-link development activity to tickets:

```
DEVX-{issue-key}: <description>

# Example
DEVX-1: add liveness probe annotation to helm values
```

Branch naming convention:

```
feature/DEVX-{issue-key}-{short-description}

# Example
feature/DEVX-1-liveness-probe
```

---

## Links

- Jira Project: https://prakashmuthukumars456.atlassian.net/jira/software/projects/DEVX/boards/34
- Confluence Space: https://prakashmuthukumars456.atlassian.net/wiki/spaces/DP/overview
- GitHub Repo: https://github.com/prakashmuthukumars456/devx-platform-engineering
