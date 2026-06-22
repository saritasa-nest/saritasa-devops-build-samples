#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

load_config

PIPELINES_URL="https://storage.googleapis.com/tekton-releases/pipeline/previous/${TEKTON_PIPELINES_VERSION}/release.yaml"
TRIGGERS_URL="https://storage.googleapis.com/tekton-releases/triggers/previous/${TEKTON_TRIGGERS_VERSION}/release.yaml"

log_info "Installing Tekton Pipelines ${TEKTON_PIPELINES_VERSION}..."
if [[ "${DRY_RUN:-false}" == "true" ]]; then
  log_info "[dry-run] kubectl apply -f ${PIPELINES_URL}"
  log_info "[dry-run] kubectl apply -f ${TRIGGERS_URL}"
  exit 0
fi

kubectl apply -f "${PIPELINES_URL}"
kubectl apply -f "${TRIGGERS_URL}"

log_info "Waiting for Tekton controllers..."
kubectl wait --for=condition=Ready pod \
  -n tekton-pipelines \
  -l app.kubernetes.io/part-of=tekton-pipelines \
  --timeout=300s 2>/dev/null || true

kubectl wait --for=condition=Ready pod \
  -n tekton-pipelines \
  -l app.kubernetes.io/part-of=tekton-triggers \
  --timeout=300s 2>/dev/null || true

for crd in tasks.tekton.dev pipelines.tekton.dev pipelineruns.tekton.dev eventlisteners.triggers.tekton.dev; do
  kubectl get crd "${crd}" >/dev/null && log_info "CRD ${crd} available"
done

log_info "Tekton installed"
