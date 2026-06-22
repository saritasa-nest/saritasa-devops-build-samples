#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

DRY_RUN=false
SKIP_MINIKUBE=false
SKIP_NGROK=false
SKIP_APPS=false

usage() {
  cat <<USAGE
Usage: $(basename "$0") [OPTIONS]

Provision Tekton CI/CD infrastructure on minikube.

Options:
  --skip-minikube   Skip minikube start/verify
  --skip-ngrok      Skip ngrok tunnel setup
  --skip-apps       Skip app Deployment generation
  --dry-run         Print steps without applying changes
  -h, --help        Show this help
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --skip-minikube) SKIP_MINIKUBE=true; shift ;;
    --skip-ngrok)    SKIP_NGROK=true; shift ;;
    --skip-apps)     SKIP_APPS=true; shift ;;
    --dry-run)       DRY_RUN=true; export DRY_RUN; shift ;;
    -h|--help)       usage; exit 0 ;;
    *) die "Unknown option: $1" ;;
  esac
done

export DRY_RUN
load_config

STEPS=(
  "00-preflight.sh"
  "01-minikube.sh"
  "02-tekton-install.sh"
  "03-namespace-rbac.sh"
  "04-secrets.sh"
)

if [[ "${SKIP_APPS}" != "true" ]]; then
  STEPS+=("05-app-deployments.sh")
fi

STEPS+=("06-tekton-resources.sh")

if [[ "${SKIP_NGROK}" != "true" ]]; then
  STEPS+=("07-ngrok.sh")
fi

for step in "${STEPS[@]}"; do
  log_info "=== Running ${step} ==="
  if [[ "${step}" == "01-minikube.sh" && "${SKIP_MINIKUBE}" == "true" ]]; then
    log_info "Skipping minikube step"
    continue
  fi
  bash "${SCRIPT_DIR}/steps/${step}"
done

log_info "=== Provision complete ==="
cat <<EOF

Next steps:
  1. Configure GitHub webhook on your fork (if not done):
     - Payload URL: see cicd/.ngrok-url or ngrok output above
     - Content type: application/json
     - Secret: value from secrets.env (GITHUB_WEBHOOK_SECRET)
     - Events: Push

  2. Tail dispatcher logs:
     kubectl logs -n ${CICD_NAMESPACE:-cicd} -l eventlistener=cicd-listener -f

  3. Tail build PipelineRuns:
     kubectl get pipelineruns -n ${CICD_NAMESPACE:-cicd} -w

  4. Run manual test:
     ./cicd/scripts/validate/test-manual-pipeline.sh

EOF
