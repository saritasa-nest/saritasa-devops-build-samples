#!/usr/bin/env bash
# Simulate dispatcher with many changed components; verify concurrency cap.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

load_config

MAX="${MAX_CONCURRENT_BUILDS:-2}"

# Build JSON array of all component paths from registry
CHANGED_FILES="$(python3 << PY
import yaml, json
with open("${CICD_ROOT}/components.yaml") as f:
    comps = yaml.safe_load(f)["components"]
files = [c["path"] + "/README.md" for c in comps[:10]]  # first 10 for quick test
print(json.dumps(files))
PY
)"

cat <<YAML | kubectl create -f -
apiVersion: tekton.dev/v1
kind: PipelineRun
metadata:
  generateName: stress-dispatcher-
  namespace: ${CICD_NAMESPACE}
spec:
  serviceAccountName: dispatcher-sa
  pipelineRef:
    name: dispatcher
  params:
    - name: git-url
      value: ${GIT_REPO_URL}
    - name: git-revision
      value: "0000000000000000000000000000000000000001"
    - name: changed-files
      value: '${CHANGED_FILES}'
  workspaces:
    - name: components
      configMap:
        name: components-registry
  timeouts:
    pipeline: 60m
YAML

log_info "Stress dispatcher PipelineRun created (10 components)"
log_info "Max concurrent builds configured: ${MAX}"
log_info "Watch running count:"
echo "  watch -n5 'kubectl get pipelinerun -n ${CICD_NAMESPACE} -l tekton.dev/pipeline=build-deploy-component | grep -c Running || true'"
