#!/usr/bin/env bash
# Trigger a single build-deploy-component PipelineRun without webhook.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

load_config
load_secrets

COMPONENT_ID="${1:-go-no-imports}"
GIT_REVISION="${2:-$(git -C "${REPO_ROOT}" rev-parse HEAD)}"
SHORT_SHA="${GIT_REVISION:0:7}"
IMAGE="${REGISTRY}/${GITHUB_USER}/${COMPONENT_ID}:${SHORT_SHA}"

# Resolve component metadata from components.yaml
read -r COMPONENT_PATH BUILDER BUILDPACK BUILD_ENV <<EOF
$(python3 << PY
import yaml, sys
with open("${CICD_ROOT}/components.yaml") as f:
    comps = yaml.safe_load(f)["components"]
for c in comps:
    if c["id"] == "${COMPONENT_ID}":
        env = c.get("build_env", {})
        env_str = ",".join(f"{k}={v}" for k, v in env.items())
        print(c["path"], c["builder"], c.get("buildpack", ""), env_str)
        sys.exit(0)
print("ERROR", file=sys.stderr)
sys.exit(1)
PY
)
EOF

cat <<YAML | kubectl create -f -
apiVersion: tekton.dev/v1
kind: PipelineRun
metadata:
  generateName: manual-build-${COMPONENT_ID}-
  namespace: ${CICD_NAMESPACE}
  labels:
    tekton.dev/pipeline: build-deploy-component
    app.kubernetes.io/component: ${COMPONENT_ID}
spec:
  serviceAccountName: pipeline-sa
  pipelineRef:
    name: build-deploy-component
  params:
    - name: git-url
      value: ${GIT_REPO_URL}
    - name: git-revision
      value: ${GIT_REVISION}
    - name: component-id
      value: ${COMPONENT_ID}
    - name: component-path
      value: ${COMPONENT_PATH}
    - name: builder
      value: ${BUILDER}
    - name: buildpack
      value: ${BUILDPACK}
    - name: build-env
      value: "${BUILD_ENV}"
    - name: image
      value: ${IMAGE}
    - name: deployment
      value: ${COMPONENT_ID}
  workspaces:
    - name: shared-source
      volumeClaimTemplate:
        spec:
          accessModes: [ReadWriteOnce]
          resources:
            requests:
              storage: 2Gi
    - name: docker-credentials
      secret:
        secretName: ghcr-credentials
  timeouts:
    pipeline: 30m
YAML

log_info "Manual PipelineRun created for ${COMPONENT_ID}"
log_info "Watch: kubectl get pipelinerun -n ${CICD_NAMESPACE} -w"
