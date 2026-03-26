# GitLab Runner on GKE with Kubernetes Executor

A self-hosted GitLab Runner using the **Kubernetes executor** on **Google Kubernetes Engine (GKE)**. Infrastructure is managed with Terraform, the runner is deployed via Helm, and RBAC is handled through explicitly managed Kubernetes manifests.

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                        GCP Project                          │
│                                                             │
│  ┌──────────────────────────────────────────────────────┐   │
│  │                   gitlab-runner-vpc                  │   │
│  │   Subnet: 10.10.0.0/24                               │   │
│  │   Pod range: 10.44.0.0/14                            │   │
│  │                                                      │   │
│  │  ┌─────────────────────────────────────────────────┐ │   │
│  │  │              GKE: gitlab-cluster                │ │   │
│  │  │                                                 │ │   │
│  │  │  Namespace: gitlab-runner                       │ │   │
│  │  │  └── Runner Manager Pod (Helm)                  │ │   │
│  │  │       └── ServiceAccount: runner-sa (WI)        │ │   │
│  │  │                                                 │ │   │
│  │  │  Namespace: gitlab-runner                       │ │   │
│  │  │  └── Job Pods                                   │ │   │
│  │  └─────────────────────────────────────────────────┘ │   │
│  └──────────────────────────────────────────────────────┘   │
│                                                             │
│  GCS Bucket: <project-id>-gitlab-runner-cache-bucket        │
│  WI: runner-sa (K8s) → gitlab-runner-sa (GCP)              │
└─────────────────────────────────────────────────────────────┘
```

**Key design decisions:**

- The runner manager and job pods run in the **same namespace** (`gitlab-runner`).
- **Workload Identity Federation** is used for keyless GCS cache access — no service account keys are stored anywhere.
- RBAC (Role, RoleBinding, ServiceAccount) is managed **outside of Helm** via explicit Kubernetes manifests, giving full control over permissions.
- The runner manager container runs with a **read-only root filesystem** and a hardened security context.

---

## Stack

| Layer | Technology |
|---|---|
| Cloud Provider | Google Cloud Platform (GCP) |
| Kubernetes | Google Kubernetes Engine (GKE) |
| Infrastructure as Code | Terraform with [Cloud Foundation Fabric](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric) modules |
| Runner Deployment | Helm (`gitlab/gitlab-runner` chart v0.87.0) |
| Cache Storage | Google Cloud Storage (GCS) |
| Identity | Workload Identity Federation (WIF) |
| Executor | Kubernetes executor |

---

## Repository Structure

```
.
├── gke.tf                    # GKE cluster, VPC, GCS bucket, and service accounts
├── variables.tf              # Terraform input variables
├── versions.tf               # Provider and Terraform version constraints
├── provider.tf               # GCP provider configuration
├── .terraform.lock.hcl       # Provider dependency lock file
│
├── gitlab-runner-role.yaml   # Kubernetes Role with minimum required RBAC permissions
├── gitlab-role-binding.yaml  # RoleBinding: runner-sa → gitlab-runner-role
├── gitlab-runner-secret.yaml # Kubernetes Secret holding the runner token (not committed)
│
├── values.yaml               # Helm values for the GitLab Runner chart
├── Makefile                  # Orchestration targets for deploy, upgrade, and teardown
└── .gitignore
```

---

## Prerequisites

The following tools must be installed and configured before deploying:

- [Terraform](https://developer.hashicorp.com/terraform/install) >= 1.7.4
- [Google Cloud SDK (`gcloud`)](https://cloud.google.com/sdk/docs/install) — authenticated with sufficient permissions
- [kubectl](https://kubernetes.io/docs/tasks/tools/)
- [Helm](https://helm.sh/docs/intro/install/) >= 3.x
- [make](https://www.gnu.org/software/make/)

GCP permissions required for the deploying identity:

- `roles/container.admin` — create and manage GKE clusters
- `roles/iam.serviceAccountAdmin` — create service accounts and manage bindings
- `roles/storage.admin` — create GCS buckets
- `roles/iam.workloadIdentityPoolAdmin` — configure Workload Identity

---

## Configuration

### 1. Runner Token (Secret)

The `gitlab-runner-secret.yaml` file is **not committed** to version control. Before deploying, create it manually:

```bash
cp gitlab-runner-secret.yaml.example gitlab-runner-secret.yaml
```

Then fill in your runner token from GitLab (`Settings → CI/CD → Runners`):

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: gitlab-runner-secret
  namespace: gitlab-runner
type: Opaque
stringData:
  runner-registration-token: "glrt-YOUR_TOKEN_HERE"
  runner-token: "glrt-YOUR_TOKEN_HERE"
```

> ⚠️ **Never commit a real token to version control.** The `.gitignore` excludes `gitlab-runner-secret.yaml` for this reason.

### 2. Makefile Variables

The `Makefile` at the top of the repo contains configuration variables. Set these before running any target:

| Variable | Description | Default |
|---|---|---|
| `PROJECT_ID` | GCP project ID | *(must be set)* |
| `REGION` | GCP region | `europe-west1` |
| `GITLAB_RUNNER_NAME` | Name shown in GitLab UI | `gke-runner` |
| `NAMESPACE` | Kubernetes namespace for runner | `gitlab-runner` |
| `K8S_SERVICE_ACCOUNT` | Kubernetes SA name | `runner-sa` |
| `GCP_PROJECT_SA` | GCP service account name | `gitlab-runner-sa` |
| `GCS_CACHE_SUFFIX` | Cache bucket name suffix | `gitlab-runner-cache-bucket` |

Pass `PROJECT_ID` at the command line to avoid editing the file:

```bash
make deploy_runner PROJECT_ID=my-gcp-project-id
```

---

## Deployment

The deployment follows a strict order. Do not skip steps.

### Step 1 — Provision Infrastructure

Deploys the VPC, GKE cluster, GCS cache bucket, and GCP service accounts via Terraform:

```bash
make deploy_cluster PROJECT_ID=my-gcp-project-id
```

### Step 2 — Configure the Cluster

Fetches GKE credentials, creates the namespace, creates the Kubernetes ServiceAccount, and annotates it for Workload Identity:

```bash
make config_cluster PROJECT_ID=my-gcp-project-id
```

This is equivalent to running:

```bash
gcloud container clusters get-credentials gitlab-cluster --zone=europe-west1
kubectl create namespace gitlab-runner
kubectl create serviceaccount runner-sa -n gitlab-runner
kubectl annotate serviceaccount runner-sa \
  -n gitlab-runner \
  iam.gke.io/gcp-service-account=gitlab-runner-sa@<PROJECT_ID>.iam.gserviceaccount.com
```

### Step 3 — Deploy the Runner

Applies the RBAC manifests and the runner secret, then installs the Helm chart:

```bash
make deploy_runner PROJECT_ID=my-gcp-project-id
```

This applies the following in order:
1. `gitlab-runner-role.yaml` — minimum-permission Role
2. `gitlab-role-binding.yaml` — binds the Role to `runner-sa`
3. `gitlab-runner-secret.yaml` — runner authentication token
4. `helm install` — installs the runner chart with all values

### All-in-one (PoC)

```bash
make deploy_runner PROJECT_ID=my-gcp-project-id
```

The `deploy_runner` target chains all three steps above automatically.

---

## Updating the Runner

After modifying `values.yaml` or Makefile variables:

```bash
make update_runner PROJECT_ID=my-gcp-project-id
```

The runner pod will restart and pick up the new ConfigMap. Verify the rollout:

```bash
kubectl rollout status deployment/gitlab-runner -n gitlab-runner
```

---

## Verifying the Deployment

```bash
# Check the runner manager pod is Running
kubectl get pod -n gitlab-runner

# Check the runner registered in GitLab
# Go to: GitLab → Group/Project → Settings → CI/CD → Runners

# Inspect the rendered Helm config without applying
make verify PROJECT_ID=my-gcp-project-id
```

---

## Security Hardening

The following security controls are applied beyond a default Helm install:

### Runner Manager Pod

| Control | Value |
|---|---|
| `readOnlyRootFilesystem` | `true` |
| `allowPrivilegeEscalation` | `false` |
| `runAsNonRoot` | `true` |
| `runAsUser` | `100` |
| `privileged` | `false` |
| `capabilities` | `drop: [ALL]` |
| `seccompProfile` | `RuntimeDefault` |

### Job Pods (Kubernetes Executor)

| Control | Value |
|---|---|
| `privileged` | `false` |
| `run_as_non_root` | `true` |
| `run_as_user` / `run_as_group` | `1000` |
| `fs_group` | `1000` |
| `capabilities.drop` | `ALL` (build, helper, service containers) |

### GCP IAM (Least Privilege)

| Service Account | Role | Scope |
|---|---|---|
| `gitlab-cluster-sa` | `logging.logWriter`, `monitoring.metricWriter`, `monitoring.viewer` | Project |
| `gitlab-runner-sa` | `storage.objectUser` | Cache bucket only |

### Workload Identity

The Kubernetes `runner-sa` ServiceAccount is bound to the GCP `gitlab-runner-sa` service account via Workload Identity. This means the runner pod can access GCS **without any service account key files** — authentication is handled transparently by the GKE metadata server.

### Graceful Shutdown

`terminationGracePeriodSeconds: 3600` is set on the runner deployment, giving in-progress jobs up to 1 hour to complete before the pod is forcefully terminated. A `preStop` lifecycle hook explicitly unregisters the runner from GitLab before the pod exits:

```yaml
preStop:
  exec:
    command: ["/entrypoint", "unregister", "--all-runners"]
```

---

## GCS Cache

The runner is configured to use a dedicated GCS bucket for distributed caching across concurrent jobs. Cache access uses Workload Identity — no credentials need to be configured manually.

Cache bucket name follows the pattern: `<PROJECT_ID>-gitlab-runner-cache-bucket`

To verify cache is working, check for `Uploading cache` / `Downloading cache` lines in your pipeline job logs.

---

## Teardown

```bash
make clean_up PROJECT_ID=my-gcp-project-id
```

This uninstalls the Helm release (triggering runner unregistration via `preStop`) and then destroys all Terraform-managed infrastructure. Kubernetes namespace and manifests applied manually are not removed by Helm — delete them if needed:

> ⚠️ `terraform destroy` is run with `--auto-approve`. Ensure no other resources depend on the VPC or cluster before running this target.
