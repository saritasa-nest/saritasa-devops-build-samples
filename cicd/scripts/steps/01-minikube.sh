#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

load_config
ensure_kubectl_context

if [[ "${DRY_RUN:-false}" == "true" ]]; then
  log_info "[dry-run] Would ensure minikube is running"
  exit 0
fi

if minikube status -f '{{.Host}}' 2>/dev/null | grep -q Running; then
  log_info "Minikube is already running"
else
  log_info "Starting minikube (memory=${MINIKUBE_MEMORY}, cpus=${MINIKUBE_CPUS})..."
  minikube start \
    --memory="${MINIKUBE_MEMORY}" \
    --cpus="${MINIKUBE_CPUS}"
fi

minikube update-context >/dev/null
kubectl cluster-info

if ! minikube addons list 2>/dev/null | grep -q metrics-server.*enabled; then
  log_info "Enabling metrics-server addon..."
  minikube addons enable metrics-server || log_warn "Could not enable metrics-server"
fi

log_info "Minikube ready"
