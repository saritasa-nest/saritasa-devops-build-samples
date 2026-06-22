#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

load_config

if [[ "${DRY_RUN:-false}" == "true" ]]; then
  log_info "[dry-run] Would start ngrok tunnel to EventListener"
  exit 0
fi

require_cmd ngrok curl

# Port-forward EventListener to localhost in background
PF_PID_FILE="${CICD_ROOT}/.port-forward.pid"
pkill -f "kubectl port-forward.*el-cicd-listener" 2>/dev/null || true
sleep 1

kubectl port-forward -n "${CICD_NAMESPACE}" \
  "service/el-cicd-listener" 8080:8080 \
  >/dev/null 2>&1 &
echo $! > "${PF_PID_FILE}"

sleep 2

pkill -f "ngrok http 8080" 2>/dev/null || true
ngrok http 8080 --log=stdout >/dev/null 2>&1 &
NGROK_PID=$!
echo "${NGROK_PID}" > "${CICD_ROOT}/.ngrok.pid"

sleep 3

TUNNEL_URL=""
for _ in $(seq 1 10); do
  TUNNEL_URL="$(curl -s "${NGROK_API_URL}/api/tunnels" 2>/dev/null \
    | python3 -c "import sys,json; d=json.load(sys.stdin); print(next((t['public_url'] for t in d.get('tunnels',[]) if t['public_url'].startswith('https')), ''))" 2>/dev/null || true)"
  [[ -n "${TUNNEL_URL}" ]] && break
  sleep 1
done

if [[ -z "${TUNNEL_URL}" ]]; then
  log_error "Could not obtain ngrok public URL. Is ngrok authenticated?"
  log_error "Run: ngrok config add-authtoken <token>"
  exit 1
fi

echo "${TUNNEL_URL}" > "${CICD_ROOT}/.ngrok-url"

cat <<EOF

========================================
GitHub Webhook Configuration
========================================
Payload URL:   ${TUNNEL_URL}
Content type:  application/json
Secret:        (value of GITHUB_WEBHOOK_SECRET in secrets.env)
Events:        Push only

Port-forward PID: $(cat "${PF_PID_FILE}")
ngrok PID:        ${NGROK_PID}
EOF

log_info "Webhook URL saved to ${CICD_ROOT}/.ngrok-url"
