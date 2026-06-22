#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

load_config
load_secrets

export CICD_NAMESPACE GITHUB_USER MAX_CONCURRENT_BUILDS REGISTRY

envsubst '${CICD_NAMESPACE} ${GITHUB_USER} ${MAX_CONCURRENT_BUILDS} ${REGISTRY}' \
  < "${CICD_ROOT}/k8s/base/namespace.yaml" | kubectl_apply -f -

kubectl_apply -f "${CICD_ROOT}/k8s/base/resource-quota.yaml"
kubectl_apply -f "${CICD_ROOT}/k8s/base/limit-range.yaml"
kubectl_apply -f "${CICD_ROOT}/k8s/rbac/"

# Mount components.yaml as ConfigMap for dispatcher
if [[ "${DRY_RUN:-false}" == "true" ]]; then
  log_info "[dry-run] kubectl create configmap components-registry from components.yaml"
else
  kubectl create configmap components-registry \
    -n "${CICD_NAMESPACE}" \
    --from-file=components.yaml="${CICD_ROOT}/components.yaml" \
    --dry-run=client -o yaml | kubectl apply -f -
fi

log_info "Namespace, RBAC, and ConfigMap applied"
