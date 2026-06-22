#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

load_config
load_secrets

[[ -n "${GITHUB_WEBHOOK_SECRET:-}" ]] || die "GITHUB_WEBHOOK_SECRET is not set"
[[ -n "${GHCR_TOKEN:-}" ]] || die "GHCR_TOKEN is not set"
[[ -n "${GITHUB_USER:-}" ]] || die "GITHUB_USER is not set"

if [[ "${DRY_RUN:-false}" == "true" ]]; then
  log_info "[dry-run] Would create secrets in ${CICD_NAMESPACE}"
  exit 0
fi

kubectl create secret generic github-webhook-secret \
  -n "${CICD_NAMESPACE}" \
  --from-literal=secretToken="${GITHUB_WEBHOOK_SECRET}" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl create secret docker-registry ghcr-credentials \
  -n "${CICD_NAMESPACE}" \
  --docker-server="${REGISTRY}" \
  --docker-username="${GITHUB_USER}" \
  --docker-password="${GHCR_TOKEN}" \
  --dry-run=client -o yaml | kubectl apply -f -

log_info "Secrets github-webhook-secret and ghcr-credentials applied"
