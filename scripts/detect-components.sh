#!/bin/bash
set -euo pipefail

# detect-components.sh - Detect modified components between two git commits
# Usage: ./detect-components.sh <old-sha> <new-sha>
# Output: Space-separated list of component paths (or "no-op" if none)

OLD_SHA="${1:-HEAD~1}"
NEW_SHA="${2:-HEAD}"
REPO_PATH="${3:-/workspace/source}"

cd "$REPO_PATH"

# List changed files
CHANGED_FILES=$(git diff --name-only "$OLD_SHA" "$NEW_SHA" 2>/dev/null || true)

if [ -z "$CHANGED_FILES" ]; then
  echo "no-op: no changes detected between $OLD_SHA and $NEW_SHA"
  exit 0
fi

# Extract unique top-level directories (components)
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

# Known buildpack-ready components
VALID_COMPONENTS=""
for path in $COMPONENTS; do
  # Check if path is a valid component directory with buildpack support
  if [ -d "$path" ] || echo "$path" | grep -qE '^(nodejs|dotnet-core|go|java|php|python|ruby)'; then
    VALID_COMPONENTS="$VALID_COMPONENTS $path"
  fi
done

if [ -z "$VALID_COMPONENTS" ]; then
  echo "no-op: no buildpack-ready components modified"
  exit 0
fi

echo "$VALID_COMPONENTS" | xargs