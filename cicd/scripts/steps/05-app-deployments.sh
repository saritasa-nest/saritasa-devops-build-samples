#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

load_config
load_secrets

APPS_DIR="${CICD_ROOT}/k8s/apps/generated"
mkdir -p "${APPS_DIR}"

python3 << PYEOF
import yaml, os

cicd_root = "${CICD_ROOT}"
apps_dir = "${APPS_DIR}"
namespace = "${CICD_NAMESPACE}"
github_user = "${GITHUB_USER}"
registry = "${REGISTRY}"

with open(os.path.join(cicd_root, "components.yaml")) as f:
    components = yaml.safe_load(f)["components"]

manifests = []
for comp in components:
    cid = comp["id"]
    port = comp.get("port", 8080)
    # Placeholder until first successful pipeline patch (public image avoids GHCR pull errors)
    image = "nginx:alpine"

    dep = {
        "apiVersion": "apps/v1",
        "kind": "Deployment",
        "metadata": {
            "name": cid,
            "namespace": namespace,
            "labels": {
                "app.kubernetes.io/name": "build-sample",
                "app.kubernetes.io/component": cid,
            },
        },
        "spec": {
            "replicas": 1,
            "selector": {"matchLabels": {"app.kubernetes.io/component": cid}},
            "template": {
                "metadata": {"labels": {"app.kubernetes.io/component": cid}},
                "spec": {
                    "imagePullSecrets": [{"name": "ghcr-credentials"}],
                    "containers": [{
                        "name": "app",
                        "image": image,
                        "ports": [{"containerPort": port}],
                        "env": [{"name": "PORT", "value": str(port)}],
                        "resources": {
                            "requests": {"cpu": "50m", "memory": "64Mi"},
                            "limits": {"cpu": "500m", "memory": "256Mi"},
                        },
                    }],
                },
            },
        },
    }

    svc = {
        "apiVersion": "v1",
        "kind": "Service",
        "metadata": {
            "name": cid,
            "namespace": namespace,
            "labels": {"app.kubernetes.io/component": cid},
        },
        "spec": {
            "selector": {"app.kubernetes.io/component": cid},
            "ports": [{"port": port, "targetPort": port}],
        },
    }

    manifests.extend([dep, svc])

kustomization = {
    "apiVersion": "kustomize.config.k8s.io/v1beta1",
    "kind": "Kustomization",
    "resources": [],
}

for comp in components:
    fname = f"{comp['id']}.yaml"
    path = os.path.join(apps_dir, fname)
    dep = next(m for m in manifests if m["kind"] == "Deployment" and m["metadata"]["name"] == comp["id"])
    svc = next(m for m in manifests if m["kind"] == "Service" and m["metadata"]["name"] == comp["id"])
    with open(path, "w") as f:
        yaml.dump_all([dep, svc], f, default_flow_style=False)
    kustomization["resources"].append(fname)

with open(os.path.join(apps_dir, "kustomization.yaml"), "w") as f:
    yaml.dump(kustomization, f, default_flow_style=False)

print(f"Generated {len(components)} deployment/service pairs in {apps_dir}")
PYEOF

if [[ "${DRY_RUN:-false}" == "true" ]]; then
  log_info "[dry-run] kubectl apply -k ${APPS_DIR}"
else
  kubectl apply -k "${APPS_DIR}"
fi

log_info "App Deployments and Services applied"
