#!/usr/bin/env bash
# Helpers for reading cicd/components.yaml.

set -euo pipefail

readonly COMPONENTS_FILE="${CICD_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}/components.yaml"

components_python() {
  python3 - "$@" << 'PY'
import sys, yaml, os

components_file = os.environ.get("COMPONENTS_FILE")
with open(components_file) as f:
    data = yaml.safe_load(f)

components = data.get("components", [])
cmd = sys.argv[1] if len(sys.argv) > 1 else "list-ids"

if cmd == "list-ids":
    for c in components:
        print(c["id"])
elif cmd == "list-paths":
    for c in components:
        print(c["path"])
elif cmd == "get-by-id":
    cid = sys.argv[2]
    for c in components:
        if c["id"] == cid:
            print(yaml.dump(c, default_flow_style=False))
            break
    else:
        sys.exit(1)
elif cmd == "match-changed":
    import json
    changed = json.loads(sys.argv[2])
    matched = {}
    paths = sorted((c["path"], c) for c in components, key=lambda x: -len(x[0]))
    for f in changed:
        f = f.lstrip("./")
        for path, comp in paths:
            if f == path or f.startswith(path + "/"):
                matched[comp["id"]] = comp
                break
    for c in matched.values():
        print(c["id"])
elif cmd == "validate-paths":
    repo = os.environ.get("REPO_ROOT", ".")
    ok = True
    for c in components:
        p = os.path.join(repo, c["path"])
        if not os.path.isdir(p):
            print(f"MISSING: {c['path']}", file=sys.stderr)
            ok = False
    sys.exit(0 if ok else 1)
else:
    print(f"Unknown command: {cmd}", file=sys.stderr)
    sys.exit(1)
PY
}

components_list_ids() {
  COMPONENTS_FILE="${COMPONENTS_FILE}" REPO_ROOT="${REPO_ROOT:-}" \
    components_python list-ids
}

components_match_changed() {
  local changed_json="$1"
  COMPONENTS_FILE="${COMPONENTS_FILE}" \
    components_python match-changed "${changed_json}"
}

components_validate_paths() {
  COMPONENTS_FILE="${COMPONENTS_FILE}" REPO_ROOT="${REPO_ROOT:-}" \
    components_python validate-paths
}
