#!/usr/bin/env bash
# Smoke test: local pack build for go and python samples before Tekton.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

BUILDER="${BUILDER:-paketobuildpacks/builder-jammy-base:latest}"

require_cmd() { command -v "$1" >/dev/null || { echo "Missing: $1"; exit 1; }; }
require_cmd pack docker

build_sample() {
  local path="$1"
  local buildpack="$2"
  local name="$3"
  echo "=== Building ${path} ==="
  pack build "${name}" \
    --path "${REPO_ROOT}/${path}" \
    --builder "${BUILDER}" \
    --buildpack "${buildpack}" \
    --trust-builder
  docker rmi "${name}" >/dev/null 2>&1 || true
}

build_sample "go/no-imports" "paketo-buildpacks/go" "smoke-go-no-imports"
build_sample "python/pip" "paketo-buildpacks/python" "smoke-python-pip"

echo "Smoke tests passed"
