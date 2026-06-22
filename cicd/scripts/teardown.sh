#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

PURGE_TEKTON=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --purge-tekton) PURGE_TEKTON=true; shift ;;
    -h|--help)
      echo "Usage: $(basename "$0") [--purge-tekton]"
      exit 0
      ;;
    *) die "Unknown option: $1" ;;
  esac
done

load_config

log_info "Stopping ngrok if running..."
pkill -f "ngrok http" 2>/dev/null || true
rm -f "${CICD_ROOT}/.ngrok-url"

log_info "Deleting namespace ${CICD_NAMESPACE}..."
if kubectl get namespace "${CICD_NAMESPACE}" >/dev/null 2>&1; then
  kubectl delete namespace "${CICD_NAMESPACE}" --wait=true
else
  log_warn "Namespace ${CICD_NAMESPACE} not found"
fi

if [[ "${PURGE_TEKTON}" == "true" ]]; then
  log_warn "Purging Tekton Pipelines and Triggers..."
  kubectl delete -f "https://storage.googleapis.com/tekton-releases/triggers/latest/release.yaml" --ignore-not-found
  kubectl delete -f "https://storage.googleapis.com/tekton-releases/pipeline/latest/release.yaml" --ignore-not-found
fi

log_info "Teardown complete (minikube cluster preserved)"
