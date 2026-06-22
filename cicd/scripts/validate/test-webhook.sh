#!/usr/bin/env bash
# POST a sample GitHub push payload to the ngrok webhook URL.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

load_config
load_secrets

NGROK_URL_FILE="${CICD_ROOT}/.ngrok-url"
[[ -f "${NGROK_URL_FILE}" ]] || die "Missing ${NGROK_URL_FILE}. Run provision.sh with ngrok first."

WEBHOOK_URL="$(cat "${NGROK_URL_FILE}")"
PAYLOAD_FILE="${SCRIPT_DIR}/validate/fixtures/github-push-sample.json"

if [[ ! -f "${PAYLOAD_FILE}" ]]; then
  mkdir -p "$(dirname "${PAYLOAD_FILE}")"
  cat > "${PAYLOAD_FILE}" <<'JSON'
{
  "ref": "refs/heads/feat-setup-tekton-cicd",
  "after": "0000000000000000000000000000000000000001",
  "repository": {
    "clone_url": "https://github.com/example/saritasa-devops-build-samples.git"
  },
  "commits": [
    {
      "added": [],
      "modified": ["go/no-imports/main.go"],
      "removed": []
    }
  ]
}
JSON
fi

compute_signature() {
  local payload="$1"
  printf '%s' "${payload}" | openssl dgst -sha256 -hmac "${GITHUB_WEBHOOK_SECRET}" | awk '{print "sha256="$2}'
}

PAYLOAD="$(cat "${PAYLOAD_FILE}")"
SIG="$(compute_signature "${PAYLOAD}")"

echo "POST ${WEBHOOK_URL}"
HTTP_CODE="$(curl -s -o /tmp/webhook-response.txt -w '%{http_code}' \
  -X POST "${WEBHOOK_URL}" \
  -H "Content-Type: application/json" \
  -H "X-GitHub-Event: push" \
  -H "X-Hub-Signature-256: ${SIG}" \
  -d "${PAYLOAD}")"

echo "HTTP ${HTTP_CODE}"
cat /tmp/webhook-response.txt
echo

if [[ "${HTTP_CODE}" =~ ^2 ]]; then
  log_info "Webhook accepted. Check: kubectl get pipelinerun -n ${CICD_NAMESPACE}"
else
  log_error "Webhook rejected"
  exit 1
fi
