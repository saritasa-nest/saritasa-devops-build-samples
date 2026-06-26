#!/usr/bin/env bash
set -euo pipefail

TEKTON_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROFILE="${MINIKUBE_PROFILE:-saritasa}"
SECRETS_FILE="${TEKTON_DIR}/secrets.env"
KUBECTL_BIN="$(command -v kubectl)"

log() { printf '[setup] %s\n' "$*"; }

kubectl() {
  export KUBECONFIG="${HOME}/.kube/config"
  minikube -p "$PROFILE" update-context >/dev/null 2>&1 || true
  "$KUBECTL_BIN" config use-context "$PROFILE" >/dev/null 2>&1 || true
  sudo -E "$KUBECTL_BIN" "$@"
}

log "Starting minikube (${PROFILE})"
minikube -p "$PROFILE" start --cpus=4 --memory=8192 --driver=docker

log "Installing Tekton"
for release in \
  pipeline/latest/release.yaml \
  triggers/latest/release.yaml \
  triggers/latest/interceptors.yaml \
  dashboard/latest/release.yaml
do
  kubectl apply -f "https://storage.googleapis.com/tekton-releases/${release}"
done
kubectl wait --for=condition=available --timeout=120s \
  deployment/tekton-pipelines-controller \
  deployment/tekton-triggers-controller \
  -n tekton-pipelines

log "Applying manifests"
kubectl apply -f "${TEKTON_DIR}/manifests/"

[[ -f "$SECRETS_FILE" ]] || { log "Missing ${SECRETS_FILE} — copy secrets.env.example"; exit 1; }
# shellcheck source=/dev/null
set -a && source "$SECRETS_FILE" && set +a
for var in GITHUB_WEBHOOK_SECRET GHCR_TOKEN GITHUB_USER; do
  [[ -n "${!var:-}" ]] || { log "Missing ${var} in secrets.env"; exit 1; }
done

log "Applying secrets"
kubectl create secret generic github-webhook-secret -n tekton \
  --from-literal=secretToken="${GITHUB_WEBHOOK_SECRET}" \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl create secret docker-registry ghcr-credentials -n tekton \
  --docker-server=ghcr.io \
  --docker-username="${GITHUB_USER}" \
  --docker-password="${GHCR_TOKEN}" \
  --dry-run=client -o yaml | kubectl apply -f -

key_file="${GIT_SSH_KEY:-${HOME}/.ssh/dknhat2000_ed25519}"
[[ -f "$key_file" ]] || { log "SSH key not found: ${key_file}"; exit 1; }

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT
ssh-keyscan -t rsa,ecdsa,ed25519 github.com >"${tmpdir}/known_hosts" 2>/dev/null
cat >"${tmpdir}/config" <<'EOF'
Host github.com
  HostName github.com
  User git
  IdentityFile ~/.ssh/id_rsa
  IdentitiesOnly yes
EOF
kubectl create secret generic git-credentials -n tekton \
  --from-file=id_rsa="${key_file}" \
  --from-file=known_hosts="${tmpdir}/known_hosts" \
  --from-file=config="${tmpdir}/config" \
  --dry-run=client -o yaml | kubectl apply -f -

if [[ -d "${TEKTON_DIR}/config" ]]; then
  log "Applying config"
  kubectl apply -f "${TEKTON_DIR}/config/"
fi

log "Applying tasks"
kubectl apply -n tekton -f "${TEKTON_DIR}/tasks/"

if [[ -d "${TEKTON_DIR}/triggers" ]]; then
  log "Applying triggers"
  kubectl apply -n tekton -f "${TEKTON_DIR}/triggers/"
fi

if command -v ngrok >/dev/null 2>&1; then
  log "Linking ngrok webhook (optional)"
  python3 "${TEKTON_DIR}/scripts/ngrok-webhook.py" || log "ngrok webhook skipped (see manual steps in script output)"
fi

log "Done"
