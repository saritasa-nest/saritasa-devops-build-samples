#!/usr/bin/env python3
import json
import os
import shutil
import subprocess
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

tekton_dir = Path(__file__).resolve().parent.parent
secrets_file = tekton_dir / "secrets.env"
profile = os.environ.get("MINIKUBE_PROFILE", "saritasa")
pf_port = os.environ.get("WEBHOOK_LOCAL_PORT", "8080")
ngrok_api = os.environ.get("NGROK_API", "http://localhost:4040")

if not secrets_file.is_file():
    print(f"[ngrok-webhook] Missing {secrets_file}")
    sys.exit(1)

secrets = {}
for line in secrets_file.read_text(encoding="utf-8").splitlines():
    line = line.strip()
    if not line or line.startswith("#"):
        continue
    key, _, value = line.partition("=")
    secrets[key.strip()] = value.strip()

webhook_secret = secrets.get("GITHUB_WEBHOOK_SECRET", "")
if not webhook_secret:
    print("[ngrok-webhook] Missing GITHUB_WEBHOOK_SECRET in secrets.env")
    sys.exit(1)

github_repo = secrets.get("GITHUB_REPO", "dknhat2000/saritasa-devops-build-samples")
github_token = secrets.get("GITHUB_TOKEN") or secrets.get("GHCR_TOKEN") or ""

if not shutil.which("ngrok"):
    print("[ngrok-webhook] ngrok not installed — skip")
    sys.exit(0)

kube_env = os.environ.copy()
kube_env["KUBECONFIG"] = f"{kube_env['HOME']}/.kube/config"
kubectl_bin = shutil.which("kubectl")
if not kubectl_bin:
    print("[ngrok-webhook] kubectl not found")
    sys.exit(1)

subprocess.run(["minikube", "-p", profile, "update-context"], env=kube_env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
subprocess.run(["kubectl", "config", "use-context", profile], env=kube_env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

check = subprocess.run(
    ["sudo", "-E", kubectl_bin, "get", "svc", "el-github-listener", "-n", "tekton"],
    env=kube_env,
    stdout=subprocess.DEVNULL,
    stderr=subprocess.DEVNULL,
)
if check.returncode != 0:
    print("[ngrok-webhook] EventListener service not found — apply triggers first")
    sys.exit(1)

pf_pattern = f"port-forward.*el-github-listener.*{pf_port}:{pf_port}"
if subprocess.run(["pgrep", "-f", pf_pattern], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode != 0:
    print(f"[ngrok-webhook] Port-forwarding EventListener → localhost:{pf_port}")
    subprocess.Popen(
        ["sudo", "-E", kubectl_bin, "port-forward", "svc/el-github-listener", f"{pf_port}:{pf_port}", "-n", "tekton"],
        env=kube_env,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    time.sleep(2)

ngrok_pattern = f"ngrok http {pf_port}"
if subprocess.run(["pgrep", "-f", ngrok_pattern], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode != 0:
    print(f"[ngrok-webhook] Starting ngrok on port {pf_port}")
    ngrok_log = open("/tmp/ngrok-tekton.log", "w", encoding="utf-8")
    subprocess.Popen(["ngrok", "http", pf_port, "--log=stdout"], stdout=ngrok_log, stderr=subprocess.STDOUT)
    time.sleep(3)

tunnel_url = ""
with urllib.request.urlopen(f"{ngrok_api}/api/tunnels", timeout=30) as resp:
    tunnels = json.loads(resp.read().decode("utf-8"))
for tunnel in tunnels.get("tunnels", []):
    url = tunnel.get("public_url", "")
    if url.startswith("https://"):
        tunnel_url = url
        break

if not tunnel_url:
    print(f"[ngrok-webhook] Could not read ngrok HTTPS URL from {ngrok_api}/api/tunnels")
    sys.exit(1)

print(f"[ngrok-webhook] Public webhook URL: {tunnel_url}")

registered = False
if github_token:
    gh_headers = {
        "Authorization": f"Bearer {github_token}",
        "Accept": "application/vnd.github+json",
        "X-GitHub-Api-Version": "2022-11-28",
    }
    hooks_url = f"https://api.github.com/repos/{github_repo}/hooks"

    try:
        req = urllib.request.Request(hooks_url, headers=gh_headers)
        with urllib.request.urlopen(req, timeout=30) as resp:
            hooks = json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as err:
        print(f"[ngrok-webhook] Cannot list webhooks (token needs admin:repo_hook on {github_repo}): {err}")
        hooks = []

    hook_id = None
    for hook in hooks:
        if "ngrok" in hook.get("config", {}).get("url", ""):
            hook_id = hook.get("id")
            break

    body = {
        "active": True,
        "events": ["push", "pull_request"],
        "config": {
            "url": tunnel_url,
            "content_type": "json",
            "secret": webhook_secret,
            "insecure_ssl": "0",
        },
    }
    if hook_id is None:
        body["name"] = "web"

    data = json.dumps(body).encode("utf-8")
    gh_headers["Content-Type"] = "application/json"

    try:
        if hook_id is not None:
            print(f"[ngrok-webhook] Updating GitHub webhook (id {hook_id})")
            target = f"{hooks_url}/{hook_id}"
            req = urllib.request.Request(target, data=data, headers=gh_headers, method="PATCH")
        else:
            print(f"[ngrok-webhook] Creating GitHub webhook on {github_repo}")
            req = urllib.request.Request(hooks_url, data=data, headers=gh_headers, method="POST")
        with urllib.request.urlopen(req, timeout=30):
            pass
        registered = True
    except urllib.error.HTTPError as err:
        print(f"[ngrok-webhook] GitHub webhook registration failed: {err.read().decode('utf-8', errors='replace')}")

if registered:
    print("[ngrok-webhook] GitHub webhook linked to EventListener via ngrok")
    print(f"[ngrok-webhook] Test: push or open/update a PR on {github_repo}")
    sys.exit(0)

if not github_token:
    print("[ngrok-webhook] No GITHUB_TOKEN in secrets.env — skipping API registration")

print("[ngrok-webhook] Register webhook manually on GitHub:")
print(f"[ngrok-webhook]   https://github.com/{github_repo}/settings/hooks/new")
print(f"[ngrok-webhook]   Payload URL: {tunnel_url}")
print("[ngrok-webhook]   Content type: application/json")
print("[ngrok-webhook]   Secret: (GITHUB_WEBHOOK_SECRET from secrets.env)")
print("[ngrok-webhook]   Events: push, pull_request")
