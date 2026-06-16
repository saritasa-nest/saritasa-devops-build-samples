#!/bin/bash
set -euo pipefail

# create-pipelineruns.sh - Create PipelineRuns for each modified component
# Usage: ./create-pipelineruns.sh <components> <image-prefix> <deployment-prefix>
# components: space-separated list of component paths
# image-prefix: registry prefix (e.g., registry.local:5000)
# deployment-prefix: optional prefix for deployments

COMPONENTS="$1"
IMAGE_PREFIX="$2"
DEPLOYMENT_PREFIX="${3:-}"
GIT_REVISION="${4:-main}"

if [ "$COMPONENTS" = "no-op" ] || [ -z "$COMPONENTS" ]; then
  echo "No components to build, exiting"
  exit 0
fi

for component in $COMPONENTS; do
  # Convert path to valid resource names (replace / with -)
  COMPONENT_NAME=$(echo "$component" | tr '/' '-')
  IMAGE="${IMAGE_PREFIX}/${COMPONENT_NAME}:${GIT_REVISION}"
  DEPLOYMENT="${DEPLOYMENT_PREFIX}${COMPONENT_NAME}-app"
  
  echo "Creating PipelineRun for $component -> $IMAGE -> $DEPLOYMENT"
  
  cat <<EOF | kubectl apply -f -
apiVersion: tekton.dev/v1beta1
kind: PipelineRun
metadata:
  name: build-${COMPONENT_NAME}-$(date +%s)
spec:
  pipelineRef:
    name: build-and-deploy
  params:
    - name: GIT_URL
      value: https://github.com/saritasa-nest/saritasa-devops-build-samples.git
    - name: GIT_REVISION
      value: ${GIT_REVISION}
    - name: COMPONENT_PATH
      value: ${component}
    - name: IMAGE
      value: ${IMAGE}
    - name: DEPLOYMENT_NAME
      value: ${DEPLOYMENT}
    - name: NAMESPACE
      value: default
  workspaces:
    - name: source
      emptyDir: {}
EOF
done