import requests
import json
import os

DD_API_KEY = os.environ['DD_API_KEY']
DD_APP_KEY = os.environ['DD_APP_KEY']
ANTHROPIC_KEY = os.environ['ANTHROPIC_API_KEY']
CONTAINER = os.environ.get('CONTAINER', 'devx-postgres')

DD_HEADERS = {
    "DD-API-KEY": DD_API_KEY,
    "DD-APPLICATION-KEY": DD_APP_KEY,
    "Content-Type": "application/json"
}

print(f"SRE Agent investigating: {CONTAINER}")

# Step 1 — Get logs from Datadog REST API
print("Querying Datadog logs...")
try:
    logs_resp = requests.post(
        "https://api.us5.datadoghq.com/api/v2/logs/events/search",
        headers=DD_HEADERS,
        json={
            "filter": {
                "query": f"container_name:{CONTAINER}",
                "from": "now-15m",
                "to": "now"
            },
            "page": {"limit": 15}
        },
        timeout=30
    )
    logs_data = logs_resp.json()
    log_lines = []
    for event in logs_data.get("data", []):
        msg = event.get("attributes", {}).get("message", "")
        ts = event.get("attributes", {}).get("timestamp", "")
        if msg:
            log_lines.append(f"[{ts}] {msg}")
    logs_text = "\n".join(log_lines) if log_lines else "No logs found"
    print(f"Got {len(log_lines)} log lines")
except Exception as e:
    logs_text = f"Log query failed: {str(e)}"
    print(f"Logs error: {e}")

# Step 2 — Get container metrics
print("Querying Datadog metrics...")
try:
    metrics_resp = requests.get(
        "https://api.us5.datadoghq.com/api/v1/query",
        headers=DD_HEADERS,
        params={
            "query": f"docker.containers.running{{container_name:{CONTAINER}}}",
            "from": int(__import__('time').time()) - 1800,
            "to": int(__import__('time').time())
        },
        timeout=30
    )
    metrics_data = metrics_resp.json()
    series = metrics_data.get("series", [])
    metrics_text = json.dumps(series[0].get("pointlist", [])[-5:]) if series else "No metrics found"
    print(f"Metrics retrieved")
except Exception as e:
    metrics_text = f"Metrics query failed: {str(e)}"
    print(f"Metrics error: {e}")

# Step 3 — Claude RCA
print("Sending to Claude for RCA...")
try:
    claude_resp = requests.post(
        "https://api.anthropic.com/v1/messages",
        headers={
            "x-api-key": ANTHROPIC_KEY,
            "anthropic-version": "2023-06-01",
            "content-type": "application/json"
        },
        json={
            "model": "claude-sonnet-4-20250514",
            "max_tokens": 500,
            "messages": [{
                "role": "user",
                "content": f"""You are an SRE agent investigating a P1 incident.

Container DOWN: {CONTAINER}

Recent logs (last 15 minutes):
{logs_text[:2000]}

Container running metric (last 30 min, last 5 points):
{metrics_text}

Provide a concise RCA with exactly 3 bullet points:
- Root cause: what caused the container to stop
- Remediation: what action was taken (container restart by SRE agent)
- Verification: what to check to confirm full recovery"""
            }]
        },
        timeout=30
    )
    diagnosis = claude_resp.json()['content'][0]['text']
    print("Claude RCA received")
except Exception as e:
    diagnosis = f"Auto-diagnosis unavailable ({str(e)}). Container {CONTAINER} was stopped and restarted by SRE agent."
    print(f"Claude error: {e}")

# Write to GitHub env
github_env = os.environ.get('GITHUB_ENV', '')
if github_env:
    safe = diagnosis.replace('\n', ' ').replace('\r', '').replace('"', "'")
    with open(github_env, 'a') as f:
        f.write(f"DIAGNOSIS={safe}\n")

print("--- DIAGNOSIS ---")
print(diagnosis)