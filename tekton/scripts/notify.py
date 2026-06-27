#!/usr/bin/env python3
"""
Print a structured build notification to stdout and post a GitHub commit
status so the result is visible on the PR.

Expected env vars (injected by the notify Task):
  COMPONENT_ID   - Component slug (e.g. go-no-imports)
  STATUS         - Tekton aggregate-status: Succeeded | Failed | Completed | None
  IMAGE_REF      - Built image reference (optional)
  COMMIT_SHA     - Git commit SHA (optional; required for GitHub status post)
  MESSAGE        - Extra detail for failures (optional)
  GITHUB_TOKEN   - GitHub PAT with repo:status scope (from github-token secret)
  GITHUB_REPO    - owner/repo slug (from build-config ConfigMap)
"""
import json
import os
import urllib.error
import urllib.request
from datetime import datetime, timezone

component_id = os.environ["COMPONENT_ID"]
status       = os.environ["STATUS"]
image_ref    = os.environ.get("IMAGE_REF", "")
commit_sha   = os.environ.get("COMMIT_SHA", "")
message      = os.environ.get("MESSAGE", "")
github_token = os.environ.get("GITHUB_TOKEN", "")
github_repo  = os.environ.get("GITHUB_REPO", "")

# ── stdout notification ───────────────────────────────────────────────────────
ts = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
print("=" * 50)
print("CICD NOTIFICATION")
print(f"timestamp:  {ts}")
print(f"status:     {status}")
print(f"component:  {component_id}")
if image_ref:
    print(f"image:      {image_ref}")
if commit_sha:
    print(f"commit:     {commit_sha}")
if message:
    print(f"message:    {message}")
print("=" * 50)

# ── GitHub commit status ──────────────────────────────────────────────────────
if not commit_sha:
    print("No commit SHA — skipping GitHub status post")
    raise SystemExit(0)

gh_state = {
    "Succeeded": "success",
    "Completed": "success",
    "Failed":    "failure",
}.get(status, "error")

payload = {
    "state":       gh_state,
    "context":     f"tekton/{component_id}",
    "description": f"Build {status}",
    "target_url":  "",
}

url = f"https://api.github.com/repos/{github_repo}/statuses/{commit_sha}"
req = urllib.request.Request(
    url,
    data=json.dumps(payload).encode(),
    headers={
        "Authorization":        f"Bearer {github_token}",
        "Accept":               "application/vnd.github+json",
        "X-GitHub-Api-Version": "2022-11-28",
        "Content-Type":         "application/json",
    },
    method="POST",
)

print(f"Posting GitHub commit status: {gh_state} (context: tekton/{component_id})")
try:
    with urllib.request.urlopen(req, timeout=15) as resp:
        print(f"GitHub status posted (HTTP {resp.status})")
except urllib.error.HTTPError as exc:
    body = exc.read().decode(errors="replace")
    print(f"WARNING: GitHub status post failed: {exc.code} {body}")
except OSError as exc:
    print(f"WARNING: GitHub status post failed: {exc}")
