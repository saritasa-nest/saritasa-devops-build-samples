#!/bin/bash
set -euo pipefail

# Test detect-components script
# Usage: ./test-detect.sh <repo-path> <old-sha> <new-sha>

REPO_PATH="${1:-/tmp/samples}"
OLD_SHA="${2:-HEAD~1}"
NEW_SHA="${3:-HEAD}"

echo "Testing component detection in $REPO_PATH"
echo "Comparing $OLD_SHA..$NEW_SHA"
echo "---"

cd "$REPO_PATH"

if ! git rev-parse --verify "$OLD_SHA" >/dev/null 2>&1; then
  echo "Error: $OLD_SHA not found, using HEAD~10"
  OLD_SHA="HEAD~10"
fi

CHANGED_FILES=$(git diff --name-only "$OLD_SHA" "$NEW_SHA" 2>/dev/null || true)

if [ -z "$CHANGED_FILES" ]; then
  echo "Result: no-op (no changes)"
  exit 0
fi

echo "Changed files:"
echo "$CHANGED_FILES"

COMPONENTS=$(echo "$CHANGED_FILES" | \
  cut -d'/' -f1-2 | \
  sort -u | \
  grep -v '^scripts$' | \
  grep -v '^tests$' | \
  grep -v '^kustomize$' | \
  grep -v '^kubernetes$' | \
  grep -v '^docker$' | \
  grep -v '^git$' | \
  grep -v '^procfile$' | \
  grep -v '^ca-certificates$' || true)

if [ -z "$COMPONENTS" ]; then
  echo "Result: no-op (no buildpack-ready components)"
else
  echo "---"
  echo "Detected components:"
  echo "$COMPONENTS"
fi