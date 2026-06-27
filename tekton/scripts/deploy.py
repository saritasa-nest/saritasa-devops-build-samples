#!/usr/bin/env python3
"""
Patch a Kubernetes Deployment with a new container image and wait for rollout.

Expected env vars (injected by the deploy Task):
  COMPONENT_ID     - Deployment name (e.g. go-no-imports)
  IMAGE_REF        - Full image reference (ghcr.io/<user>/<id>:<sha>)
  NAMESPACE        - Kubernetes namespace (default: tekton)
  ROLLOUT_TIMEOUT  - Rollout wait timeout in seconds (default: 300)
"""
import os
import sys
import time

from kubernetes import client, config
from kubernetes.client.rest import ApiException

component_id    = os.environ["COMPONENT_ID"]
image_ref       = os.environ["IMAGE_REF"]
namespace       = os.environ.get("NAMESPACE", "tekton")
timeout_seconds = int(os.environ.get("ROLLOUT_TIMEOUT", "300"))

config.load_incluster_config()
apps_v1 = client.AppsV1Api()


def patch_deployment() -> None:
    dep = apps_v1.read_namespaced_deployment(component_id, namespace)
    container_name = dep.spec.template.spec.containers[0].name

    patch = {
        "spec": {
            "template": {
                "spec": {
                    "containers": [{"name": container_name, "image": image_ref}]
                }
            }
        }
    }
    apps_v1.patch_namespaced_deployment(component_id, namespace, patch)
    print(f"Patched deployment/{component_id} → {image_ref}")


def wait_for_rollout() -> None:
    deadline = time.time() + timeout_seconds
    while time.time() < deadline:
        dep = apps_v1.read_namespaced_deployment(component_id, namespace)
        spec_replicas = dep.spec.replicas or 1
        st = dep.status
        updated   = st.updated_replicas or 0
        ready     = st.ready_replicas or 0
        available = st.available_replicas or 0

        print(
            f"Rollout: updated={updated}/{spec_replicas} "
            f"ready={ready}/{spec_replicas} "
            f"available={available}/{spec_replicas}"
        )

        if updated == spec_replicas and ready == spec_replicas and available == spec_replicas:
            print(f"Rollout complete: deployment/{component_id}")
            return

        time.sleep(5)

    print(f"ERROR: rollout timed out after {timeout_seconds}s", file=sys.stderr)
    dump_pod_events()
    sys.exit(1)


def dump_pod_events() -> None:
    """Print recent pod events to help diagnose a failed rollout."""
    try:
        core_v1 = client.CoreV1Api()
        events = core_v1.list_namespaced_event(
            namespace,
            field_selector=f"involvedObject.name={component_id}",
        )
        print("\nRecent events:")
        for ev in sorted(events.items, key=lambda e: e.last_timestamp or e.event_time or ""):
            print(f"  {ev.reason}: {ev.message}")
    except ApiException:
        pass


patch_deployment()
wait_for_rollout()
