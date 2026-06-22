#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

load_config

kubectl_apply -k "${CICD_ROOT}/k8s/tekton/"

log_info "Tekton Tasks, Pipelines, and Triggers applied"
