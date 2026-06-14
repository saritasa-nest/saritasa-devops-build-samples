# Tekton Documentation

## Environment

- K8S environment: Minikube
- K8S version: v1.33.0
- Linux environment: WSL2
- Linux Distro: Ubuntu 24.04

## Note

- You may need to adjust all Tekton resources' namespace to your prefered namespace. They MUST be in the same namespace with Repository CR's namespace.
- You need to adjust the `image-registry` value in file `.tekton/pull-request.yaml` and `.tekton/feature-push.yaml` to your Docker registry.

## Folder Structure

```sh
.tekton/
|__ README.md  # README for configuring Tekton's Pipeline-as-Code in this repository
|__ feature-push.yaml  # Tekton's PipelineRun triggered when pushing to features/** branches
|__ pull-request.yaml  # Tekton's PipelineRun triggered when making PR to "main" branch
|__ ingress.yaml  # Manifests for 2 ingresses: webhook & dashboard
|__ pvc.yaml  # PVC manifest for containing source code for PipelineRuns
|__ rbac.yaml  # RBAC manifests to configure additional Cluster Role and binding for Service Account that runs all pipelines
|__ pipelines/
    |__ main.yaml  # The upstream Pipeline manifest called when receiving webhook events
    |__ trigger-build-component.yaml  # The downstream Pipeline manifest called when each project has changes
|__ tasks/
    |__ build-push-image.yaml  # Task for building & pushing OCI images
    |__ create-tekton-resources.yaml  # Task to provision Tekton resources in ".tekton" folder
    |__ deploy-to-kubernetes.yaml  # Task to deploy each project's OCI image to current Kubernetes cluster
    |__ detect-changed-components.yaml  # Task to detect which project folders have changes
    |__ git-clone.yaml  # Task to clone this repository using Git
    |__ trigger-components-build.yaml  # Task to trigger 1 PipelineRun for each project folder with changes
|__ templates/
    |__ component-build-run-template.yaml  # A PipelineRun template with dynamically substitutable values for each project
```

## Alternative

I have prepared another way to set up Tekton and Pipeline-as-Code for this project using `Taskfile`. It's a fast, cross-platform build tool inspired by Make. It supports you to run all these setups in an automated way.

I put a `Taskfile.yaml` at the root of this repository. This file defines all the tasks needed to run to set up this repository. Please read the file to get the gist of it.

To be able to run `Taskfile`, you need to install its client following this [guide](https://taskfile.dev/docs/installation).

```sh
brew install go-task/tap/go-task
```

To first get used to `Taskfile`, you may run these commands:

```sh
task --help

# List out all tasks for current project
task default
```

Refer to Taskfile's [documentation](https://taskfile.dev/docs/getting-started) for further information.

## Prerequisites

Before you begin, make sure you have the following in place:

- A local Kubernetes cluster like Kind or Minikube
- The **Tekton Pipelines** installed on your cluster
- The **Tekton CLI** installed, and the **Pipelines-as-Code CLI plugin** (`tkn-pac`) installed

## Installation

Use command below to install **Tekton Pipeline**

```sh
kubectl apply --filename https://infra.tekton.dev/tekton-releases/pipeline/latest/release.yaml
```

Install **Tekton CLI**

```sh
TKN_CLI_VERSION=0.43.2
curl -LO "https://github.com/tektoncd/cli/releases/download/v${TKN_CLI_VERSION}/tektoncd-cli-${TKN_CLI_VERSION}_Linux-64bit.deb"
sudo dpkg -i "./tektoncd-cli-${TKN_CLI_VERSION}_Linux-64bit.deb"
sudo rm "./tektoncd-cli-${TKN_CLI_VERSION}_Linux-64bit.deb"

# For verifying
tkn version
```

Install **Tekton Pipeline-as-code** `tkn-pac`

```sh
TKN_PAC_VERSION=0.39.7
curl -LO "https://github.com/tektoncd/pipelines-as-code/releases/download/v${TKN_PAC_VERSION}/tkn-pac-${TKN_PAC_VERSION}_linux-x86_64.deb"
sudo dpkg -i "./tkn-pac-${TKN_PAC_VERSION}_linux-x86_64.deb"
sudo rm "./tkn-pac-${TKN_PAC_VERSION}_linux-x86_64.deb"

# For verifying
tkn pac version
```

Install **Gosmee**. This is a webhook relay server to relay Github Webhook to your internal Tekton Pipelines

```sh
GOSMEE_VERSION=0.31.1
curl -LO "https://github.com/chmouel/gosmee/releases/download/v${GOSMEE_VERSION}/gosmee-${GOSMEE_VERSION}_linux-x86_64.deb"
sudo dpkg -i "./gosmee-${GOSMEE_VERSION}_linux-x86_64.deb"
sudo rm "./gosmee-${GOSMEE_VERSION}_linux-x86_64.deb"

# For verifying
gosmee --version
```

### Optional Dependencies

#### Tekton Dashboard

Install the dashboard

```sh
# By default, Tekton Dashboard is installed READONLY mode.
kubectl apply --filename https://infra.tekton.dev/tekton-releases/dashboard/latest/release.yaml

# If you want to install Tekton Dashboard with READ-WRITE mode, use command below.
kubectl apply --filename https://infra.tekton.dev/tekton-releases/dashboard/latest/release-full.yaml
```

To access dashboard, create an Ingress resource.

```sh
DASHBOARD_URL="dashboard.saritasa.test.com"
DASHBOARD_PATH="/"
kubectl apply -n tekton-pipelines -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: dashboard-ingress
  namespace: tekton-pipelines
spec:
  rules:
  - host: $DASHBOARD_URL
    http:
      paths: 
      - pathType: Prefix
        path: $DASHBOARD_PATH
        backend:
          service:
            name: tekton-dashboard
            port:
              number: 9097
EOF
```

## Implementation

### Enable Ingress Controller Addons (Optional)

***Note***: If the addon is enabled in your Minikube cluster, then you don't need to run this step.

You will need a route for the webhook to work successfully, you need to enable the ingress controller addon.

```sh
minikube addons enable ingress
```

### Create a public route for webhook

Run below command to create an ingress

```sh
WEBHOOK_URL=hook.saritasa.test.com
WEBHOOK_PATH=/
kubectl apply -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: pipeline-as-code-controller-ingress
  namespace: pipelines-as-code
spec:
  rules:
  - host: $WEBHOOK_URL
    http:
      paths:
      - pathType: Prefix
        path: $WEBHOOK_PATH
        backend:
          service:
            name: pipelines-as-code-controller
            port:
                number: 8080
EOF
```

### Setup Gosmee as Webhook Relay

Now, you need to set up a webhook relay server because you are hosting your CI system in a local K8s cluster. Go to this endpoint [https://hook.pipelinesascode.com/](https://hook.pipelinesascode.com/) to create a public endpoint so your Github Webhook can send its events to. This endpoint will create a unique endpoint.

Then, you configure `gosmee` client to relay events from [https://hook.pipelinesascode.com/](https://hook.pipelinesascode.com/) to your local CI system

```sh
gosmee client https://hook.pipelinesascode.com/<unique-id> http://hook.saritasa.test.com
```

***Note***: After setting relay server, you need to open new terminal to continue running the setup because `gosmee` keeps running in the foreground in the current terminal.

### Expose Minikube

To enable traffics routed to Minikube, you need to create a tunnel to expose those ingresses for public traffics to route.

```sh
minikube tunnel
```

***Note***: After running command above, you need to open new terminal to continue running the setup because `minikube tunnel` keeps running in the foreground in the current terminal.

### Initialize a Github App

Initialize a Github App for the Tekton's Pipeline as a recommended way in the official document. The Github App already sets up a webhook between Tekton and your repo. You may be asked some questions to set up the app.

```sh
tkn pac bootstrap

# You will be asked
=> Checking if Pipelines-as-Code is installed.
🕵️ Pipelines as Code doesn't seems to be installed in pipelines-as-code namespace
? Do you want me to install Pipelines as Code v0.48.0? Yes
✓ Pipelines-as-Code v0.48.0 has been installed
👀 We have detected a tekton dashboard install on http://dashboard.saritasa.test.com
? Do you want me to use it? Yes
? Enter the name of your GitHub application:  <Name of your GitHub App>
? Enter your public route URL:  <Public Webhook Endpoint>
```

***Note***: Run this command from the root of this repository.

### Add GitHub App's permissions to this repository

After bootstraping this repo, you need to follow the **Github** link returned by `tkn pac` command to add permissions to this repo for the GitHub App you just created.

Steps to perform:

- Go to the GitHub App URL provided by `tkn pac bootstrap`
- Click on the “Install” button.
- Choose the repository you just created under your username.

*Refer to this [link](https://pipelinesascode.com/docs/getting-started/#install-the-github-application-on-your-repository) for more info.*

***Note***: For security reasons, you should scope down repository access to this repo only.

### Create a Repository CR

Register current repo as Repository CR managed by Tekton.

```sh
tkn pac create repository

# You will be asked
? Enter the Git repository URL :  <Current repo URL>
? Please enter the namespace where the pipeline should run (default: default): <Namespace for containing pipeline runs>
```

### Create a Kubernetes secret to access Docker Registry

Use this command to create a K8S secret to hold content of the Docker's `config.json` file. This secret is then used for a task to push image to Docker registry.

```sh
kubectl create secret generic docker-config --from-file=config.json="$HOME/.docker/config.json" -n $(k get repository -A -o jsonpath='{.items[0].metadata.namespace}')
```

### Add concurrency limit to Repository CR

Set concurrency limit to prevent Tekton from triggering all PiplineRuns, which might abuse all of cluster resources.

```sh
k patch repositories.pipelinesascode.tekton.dev $(k get repository -A -o jsonpath='{.items[0].metadata.name}') -p '{"spec":{"concurrency_limit":2}}' --type 'merge' -n $(k get repository -A -o jsonpath='{.items[0].metadata.namespace}')
```

### Add permissions to pipeline's Service Account

Since the pipeline are built to trigger other pipelines, it needs permissions to interact with different kinds of K8S resources in the cluster. There is a YAML file for setting permissions to pipeline's service account at `.tekton/rbac.yaml`.

Run this command apply it.

```sh
kubectl apply -f .tekton/rbac.yaml
```

### Provision a PVC to contain source code

Since Tekton Pipeline-as-Code allows pipelines to create PVCs to host source code for `git-clone` task on each run, this would cause management overhead to be really high. Therefore, you can create a predefined PVC and do not need to manually manage PVCs created for each run.

```sh
kubectl apply -f .tekton/pvc.yaml
```

## How to run?

There's no difficulty in running Tekton pipeline. All you need to do is *update your subproject code and commit them to GitHub*. Because all events are managed by Tekton's Pipeline-as-Code (PAC), which is a Git-native CI/CD framework in Tekton ecosystem, when there's a webhook event sent from GitHub, PAC automatically watches and triggers corresonding PipelineRun based on the event type.

