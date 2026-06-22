# Saritasa DevOps CI/CD

Tekton-based CI/CD for Paketo buildpack sample applications on local minikube.

## Quick start

1. Fork this repository on GitHub.
2. Copy configuration files:
   ```bash
   cp cicd/config.env.example cicd/config.env
   cp cicd/secrets.env.example cicd/secrets.env
   # Edit secrets.env with GITHUB_USER, GHCR_TOKEN, GITHUB_WEBHOOK_SECRET
   ```
3. Provision infrastructure:
   ```bash
   ./cicd/scripts/provision.sh
   ```
4. Configure GitHub webhook on your fork using the printed ngrok URL.
5. Push a commit changing a sample component (e.g. `go/no-imports/main.go`).

See [cicd/docs/SETUP.md](cicd/docs/SETUP.md) for the full runbook.

## Documentation

- [Setup guide](cicd/docs/SETUP.md)
- [Architecture](cicd/docs/ARCHITECTURE.md)
- [Testing](cicd/docs/TESTING.md)

## Layout

```
cicd/
  components.yaml       # Registry of buildpack-ready sample paths
  scripts/provision.sh  # Main provision orchestrator
  k8s/                  # Kubernetes and Tekton manifests
  docs/                 # Documentation
```
