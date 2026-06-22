# Setup Guide

This guide provisions Tekton CI/CD on minikube with GHCR and GitHub webhooks.

## Prerequisites

- minikube (already installed)
- kubectl
- python3 + PyYAML (`pip install pyyaml` for local scripts)
- ngrok (authenticated: `ngrok config add-authtoken <token>`)
- envsubst (`gettext` package)
- pack CLI (optional, for smoke tests)
- GitHub fork of this repository

## GitHub credentials

### GHCR Personal Access Token

Create a classic PAT with scopes:

- `write:packages`
- `read:packages`
- `delete:packages` (optional)

### Webhook secret

Generate a random string:

```bash
openssl rand -hex 32
```

## Configuration

```bash
cp cicd/config.env.example cicd/config.env
cp cicd/secrets.env.example cicd/secrets.env
```

Edit `cicd/secrets.env`:

```bash
export GITHUB_USER="your-github-username"
export GHCR_TOKEN="ghp_..."
export GITHUB_WEBHOOK_SECRET="your-random-secret"
```

Edit `cicd/config.env` if needed:

- `GIT_REPO_URL` — your fork clone URL
- `MAX_CONCURRENT_BUILDS` — default `2` (resource control)
- `MINIKUBE_MEMORY` / `MINIKUBE_CPUS` — cluster sizing

## Provision

```bash
chmod +x cicd/scripts/**/*.sh cicd/scripts/*.sh
./cicd/scripts/provision.sh
```

Options:

| Flag | Description |
|------|-------------|
| `--skip-minikube` | Cluster already running |
| `--skip-ngrok` | In-cluster only |
| `--skip-apps` | Skip Deployment generation |
| `--dry-run` | Print steps only |

## GitHub webhook

After provision, configure on your fork:

| Field | Value |
|-------|-------|
| Payload URL | From `cicd/.ngrok-url` or provision output |
| Content type | `application/json` |
| Secret | Same as `GITHUB_WEBHOOK_SECRET` |
| Events | Push |

## Verify

```bash
# Local pack smoke test (optional)
./cicd/scripts/validate/smoke-pack-local.sh

# Manual PipelineRun (no webhook)
./cicd/scripts/validate/test-manual-pipeline.sh go-no-imports

# Webhook test
./cicd/scripts/validate/test-webhook.sh
```

## Monitor logs

```bash
# EventListener
kubectl logs -n cicd -l eventlistener=cicd-listener -f

# Dispatcher / build PipelineRuns
kubectl get pipelinerun -n cicd -w

# Task pod logs
kubectl logs -n cicd -l tekton.dev/pipeline=build-deploy-component -f
```

## Teardown

```bash
./cicd/scripts/teardown.sh
# Remove Tekton CRDs (destructive):
./cicd/scripts/teardown.sh --purge-tekton
```

## Troubleshooting

| Problem | Fix |
|---------|-----|
| ngrok URL empty | Run `ngrok config add-authtoken`; restart provision |
| GHCR push denied | Verify PAT scopes; check `ghcr-credentials` secret |
| pack OOM | Increase minikube memory; lower `MAX_CONCURRENT_BUILDS` |
| Webhook 401 | Secret mismatch between GitHub and `secrets.env` |
| Image pull error on deploy | Ensure `imagePullSecrets: ghcr-credentials` on Deployment |
