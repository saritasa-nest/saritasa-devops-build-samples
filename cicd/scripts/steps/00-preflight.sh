#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"
# shellcheck source=../lib/components.sh
source "${SCRIPT_DIR}/lib/components.sh"

load_config

require_cmd kubectl minikube python3 curl envsubst

log_info "Preflight checks passed"
log_info "Components file: ${COMPONENTS_FILE}"
log_info "Registered components: $(components_list_ids | wc -l)"

REPO_ROOT="${REPO_ROOT}" components_validate_paths && log_info "All component paths exist on disk"
