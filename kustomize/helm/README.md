# CRM Helm & Kustomize Deployment

This repository contains an example of **kustomize** usage with helm chart and **kustomize** overlays to deploy a sample application built on top of [stakater/application](https://github.com/stakater/application) helm chart and its worker in multiple environments.

> This mimics infra-v3 solution

## Overview

- **Helm Chart** (`helm-charts/crm`): An umbrella chart (API v2) that pulls in two dependencies (both using the [stakater/application](https://artifacthub.io/packages/helm/stakater/application) v6.5.0) under the aliases `crm` and `worker`.
- **Environments**: Two Kustomize overlays - `staging/` and `prod/` provide environment-specific configuration, including ingress host, Helm values overrides, and image tags.

## Prerequisites

- Kubernetes cluster (v1.14+)
- `kubectl` v1.14+
- `Helm` v3 (for dependency management)
- `kustomize` v4+ (with built-in Helm chart support via `helmCharts`)

## Helm Chart: `helm-charts/crm`

Since `kustomize` can't auto-build the dependencies, they are added to the repository.

### Chart Details

- Chart API Version: v2 (umbrella)
- Chart Name: **crm**
- Version: 1.0.0 (appVersion 1.0.0)
- Dependencies (in `Chart.yaml`):
  - alias `crm`: `application` v6.5.0 from  [stakater/application](https://github.com/stakater/application)
  - alias `worker`: `application` v6.5.0 from  [stakater/application](https://github.com/stakater/application)

### Update Dependencies

> Since `kustomize` can't auto-build the dependencies, they are added to the repository.

```bash
helm dependency update helm-charts/crm
```  

This populates `helm-charts/crm/charts/` with the required `.tgz` packages.

### Default Values

See `helm-charts/crm/values.yaml` for default settings of both subcharts (images, commands, ingress, jobs, autoscaling, etc.).

## Kustomize Overlays

Each environment folder (`staging/`, `prod/`) contains:

- `environment.properties`: Key-value pairs for environment-specific variables (e.g., `HOST=...`).
- `values.yaml`: Helm values overrides for the chart.
- `kustomization.yaml`: Main Kustomize config.

### kustomization.yaml

- `namespace`: Kubernetes namespace to deploy into.
- `configMapGenerator`: Generates a ConfigMap (`crm-ingress-properties`) from `environment.properties`.
- `helmGlobals.chartHome`: Path to the local Helm charts (`../helm-charts`).
- `helmCharts`: Defines the Helm chart to render:
  - `name`: Chart directory name (`crm`).
  - `releaseName`: Helm release name (`crm`).
  - `valuesFile`: Overlay-specific `values.yaml`.
  - `valuesMerge: merge`: Merge overlay values into the default.
- `vars`: Declares a variable `HOST` by reading `data.HOST` from the generated ConfigMap.  
  These vars can be interpolated in Helm chart values using the `$(HOST)` placeholder.
- `images`: Overrides container images (by chart alias) with `newName` and `newTag` for environment-specific registries/tags.

## Deploying

1. **Ensure Helm dependencies are up to date**:

   ```bash
   helm dependency update helm-charts/crm
   ```

2. **Deploy to Staging**:

   ```bash
   kustomize build staging | kubectl apply -f -
   ```

3. **Deploy to Production**:

   ```bash
   kustomize build prod | kubectl apply -f -
   ```

## Customization

- To add a new environment, copy one of the existing overlays (`staging/` or `prod/`) and update:
  - `environment.properties` for the ingress host
  - `values.yaml` for Helm value overrides
  - `kustomization.yaml` for image tags, namespace, etc.
- To override additional images or subchart values, update the `images` and `valuesFile` sections in the overlay's `kustomization.yaml`.