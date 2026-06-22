#!/usr/bin/env bash
# Shared helpers for cicd provision scripts.

set -euo pipefail

readonly CICD_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
readonly REPO_ROOT="$(cd "${CICD_ROOT}/.." && pwd)"
export CICD_ROOT REPO_ROOT

log_info()  { printf '[INFO]  %s\n' "$*"; }
log_warn()  { printf '[WARN]  %s\n' "$*" >&2; }
log_error() { printf '[ERROR] %s\n' "$*" >&2; }

die() {
  log_error "$@"
  exit 1
}

load_config() {
  local config_file="${CICD_ROOT}/config.env"
  if [[ -f "${config_file}" ]]; then
    # shellcheck disable=SC1090
    source "${config_file}"
  elif [[ -f "${CICD_ROOT}/config.env.example" ]]; then
    # shellcheck disable=SC1090
    source "${CICD_ROOT}/config.env.example"
    log_warn "Using config.env.example defaults; copy to config.env to customize"
  fi
}

load_secrets() {
  local secrets_file="${CICD_ROOT}/secrets.env"
  [[ -f "${secrets_file}" ]] || die "Missing ${secrets_file}. Copy secrets.env.example and fill values."
  # shellcheck disable=SC1090
  source "${secrets_file}"
}

require_cmd() {
  local cmd
  for cmd in "$@"; do
    command -v "${cmd}" >/dev/null 2>&1 || die "Required command not found: ${cmd}"
  done
}

kubectl_apply() {
  if [[ "${DRY_RUN:-false}" == "true" ]]; then
    log_info "[dry-run] kubectl apply $*"
  else
    kubectl apply "$@"
  fi
}

wait_for_pods() {
  local namespace="$1"
  local selector="$2"
  local timeout="${3:-300}s"
  log_info "Waiting for pods (${selector}) in ${namespace}..."
  if [[ "${DRY_RUN:-false}" == "true" ]]; then
    return 0
  fi
  kubectl wait --for=condition=Ready pod \
    -n "${namespace}" \
    -l "${selector}" \
    --timeout="${timeout}" 2>/dev/null || {
      log_warn "Some pods may not be Ready yet; check: kubectl get pods -n ${namespace} -l ${selector}"
    }
}

ensure_kubectl_context() {
  local expected="${KUBE_CONTEXT:-minikube}"
  local current
  current="$(kubectl config current-context 2>/dev/null || true)"
  if [[ "${current}" != "${expected}" ]]; then
    log_warn "Current context is '${current}', expected '${expected}'"
    if command -v minikube >/dev/null 2>&1; then
      minikube update-context >/dev/null 2>&1 || true
    fi
  fi
}
