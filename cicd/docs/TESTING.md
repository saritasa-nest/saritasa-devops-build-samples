# Testing Guide

## Test matrix

| # | Scenario | How to test | Expected result |
|---|----------|-------------|-----------------|
| 1 | Invalid webhook secret | POST payload with wrong HMAC | HTTP 401/403; no PipelineRun |
| 2 | No-op push | Push commit changing only root README | Dispatcher logs `NOOP`; no build runs |
| 3 | Single component | Change `go/no-imports/main.go` | 1 build PipelineRun; Deployment patched |
| 4 | Multi component | Change go + python in one commit | 2 build PipelineRuns |
| 5 | Stress / concurrency | Change many components | Max 2 concurrent builds; others queued |
| 6 | Build failure | Break a sample intentionally | Failed PipelineRun; failure in stdout |

## Automated scripts

### Smoke test (local pack)

```bash
./cicd/scripts/validate/smoke-pack-local.sh
```

Builds `go/no-imports` and `python/pip` locally with pack.

### Manual PipelineRun

```bash
./cicd/scripts/validate/test-manual-pipeline.sh go-no-imports
./cicd/scripts/validate/test-manual-pipeline.sh python-pip
```

Bypasses webhook; tests clone → build → push → patch end-to-end.

### Webhook test

```bash
./cicd/scripts/validate/test-webhook.sh
```

POSTs sample GitHub push payload with valid HMAC to ngrok URL.

### Stress test

```bash
./cicd/scripts/validate/test-stress.sh
```

Creates dispatcher PipelineRun with 10 changed components. Verify concurrency:

```bash
watch -n5 'kubectl get pipelinerun -n cicd -l tekton.dev/pipeline=build-deploy-component'
```

Running count should not exceed `MAX_CONCURRENT_BUILDS`.

## Manual GitHub tests

1. Configure webhook on fork (see SETUP.md).
2. Commit change to single component:
   ```bash
   echo "// test" >> go/no-imports/main.go
   git commit -am "test: trigger go build"
   git push
   ```
3. Watch PipelineRuns:
   ```bash
   kubectl get pipelinerun -n cicd -w
   ```
4. Verify deployment:
   ```bash
   kubectl get deployment go-no-imports -n cicd -o jsonpath='{.spec.template.spec.containers[0].image}'
   ```

## Invalid secret test

```bash
curl -X POST "$(cat cicd/.ngrok-url)" \
  -H "Content-Type: application/json" \
  -H "X-GitHub-Event: push" \
  -H "X-Hub-Signature-256: sha256=invalid" \
  -d '{"ref":"refs/heads/main"}'
```

## Log locations

```bash
# EventListener
kubectl logs -n cicd -l eventlistener=cicd-listener --tail=100

# Dispatcher
kubectl logs -n cicd -l tekton.dev/pipeline=dispatcher --tail=100

# Build task pods
kubectl get pods -n cicd -l tekton.dev/pipeline=build-deploy-component
kubectl logs -n cicd <pod-name> --all-containers
```

## Success criteria

- Webhook secret validated on every request
- One PipelineRun per changed component
- Images pushed to GHCR with commit SHA tag
- Deployments patched (not created from scratch)
- stdout notifications on success and failure
- Cluster survives "change all components" push without OOM
