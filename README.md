# GitLab Runner on GKE — Terragrunt Infrastructure

## Overview

This project provisions a GitLab CI/CD runner fleet on Google Kubernetes Engine (GKE) using **Terragrunt** as the infrastructure orchestration layer on top of custom Terraform modules. The primary goal of this repository is to practice and demonstrate Terragrunt’s infrastructure management capabilities — including root configuration inheritance, module sourcing, dependency chaining, remote state management, and provider generation — all against a real GCP-based runner platform.

The infrastructure is split into two logical tiers:

1. **Shared cluster resources** — VPC, GKE cluster, IAM service accounts, and GCS cache bucket, provisioned once and shared across all runners.
1. **Per-runner node pools** — independently sized and independently deployable GKE node pools (`runner-L`, `runner-M`, `runner-XL`), each declared as its own Terragrunt unit.

-----

## Repository Structure

```
.
├── modules/
│   ├── shared-gke-resources/       # Custom TF module: VPC, GKE cluster, IAM, GCS
│   │   ├── gke.tf
│   │   ├── iam.tf
│   │   ├── storage.tf
│   │   ├── vpc.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   └── node-pools/                 # Custom TF module: GKE node pool
│       ├── main.tf
│       ├── variables.tf
│       └── outputs.tf
├── runners/
│   ├── root.hcl                    # Terragrunt root config (providers, backend, locals)
│   ├── shared-cluster/
│   │   └── terragrunt.hcl          # Terragrunt unit: cluster + networking + IAM + GCS
│   ├── runner-L/
│   │   └── terragrunt.hcl          # Terragrunt unit: n2-standard-2 node pool
│   ├── runner-M/
│   │   └── terragrunt.hcl          # Terragrunt unit: e2-standard-2 node pool
│   └── runner-XL/
│       └── terragrunt.hcl          # Terragrunt unit: n2d-standard-2 node pool
└── cluster-config/                 # Helm values & RBAC manifests (out of TG scope)
```

-----

## Custom Terraform Modules

### `modules/shared-gke-resources`

A composite module that provisions all shared infrastructure in a single apply. It intentionally groups resources that have a shared lifecycle — you create them once, and all runner node pools consume them.

**Resources managed:**

|Resource                           |Description                                                                                                               |
|-----------------------------------|--------------------------------------------------------------------------------------------------------------------------|
|`google_compute_network`           |Custom VPC (`runner-vpc`) with MTU 1460, no auto-subnets                                                                  |
|`google_compute_subnetwork`        |Subnets with configurable secondary IP ranges for GKE pods/services                                                       |
|`google_container_cluster`         |Regional GKE cluster (`gitlab-cluster`) with default node pool removed, Workload Identity enabled, REGULAR release channel|
|`google_service_account`           |Dynamically creates multiple SAs from a `map(object(...))` input                                                          |
|`google_project_iam_member`        |Flattens project-level roles per SA using `merge` + `for` expression                                                      |
|`google_service_account_iam_member`|Handles cross-resource IAM bindings (e.g. WIF principal → SA token creator)                                               |
|`google_storage_bucket`            |GCS bucket(s) for GitLab runner cache                                                                                     |
|`google_storage_bucket_iam_binding`|Optional per-bucket IAM bindings                                                                                          |

**Notable design patterns:**

- IAM bindings are fully data-driven. Both `iam_project_roles` (project-level) and `iam` (resource-level bindings to arbitrary principals) are expressed as structured inputs and flattened into `for_each`-compatible maps using nested `merge([for ...]...)` expressions.
- The `service_accounts` variable includes an inline `validation` block that enforces that all IAM principals conform to the `serviceAccount:`, `user:`, or `group:` prefix format.
- Workload Identity is toggled via `optional(bool, true)` on the GKE cluster variable, rendered as a `dynamic` block — present only when enabled.
- The VPC subnet supports multiple secondary IP ranges via a `dynamic "secondary_ip_range"` block, keeping the interface clean for GKE alias IP configuration.

### `modules/node-pools`

A focused single-resource module that provisions a `google_container_node_pool`. Each runner size maps to its own instance of this module, deployed through a dedicated Terragrunt unit.

**Key characteristics:**

- Autoscaling is always enabled (`min_node_count` / `max_node_count`).
- A `NO_SCHEDULE` taint (`runner-size=<pool-name>`) is applied to every node, ensuring that only pods explicitly tolerating that taint are scheduled — i.e., GitLab runner pods targeting that size tier.
- `workload_metadata_config` defaults to `GKE_METADATA` mode, which restricts pod access to node metadata and is required for Workload Identity to function correctly.
- A `validation` block on `machine_type` enforces an explicit allowlist: `e2-standard-2`, `n2-standard-2`, `n2d-standard-2` — preventing misconfigured pools at plan time.

-----

## Terragrunt Configuration

### `runners/root.hcl` — Root Configuration

The root HCL is the single source of truth for all cross-cutting infrastructure concerns. Every Terragrunt unit in the `runners/` directory inherits it via `include { path = find_in_parent_folders("root.hcl") }`.

**What `root.hcl` provides:**

**1. External config loading**

All environment-specific values (`project_id`, `region`, `backend_bucket`, `impersonate_sa`, module refs) are loaded from an external `config.yaml` via `yamldecode(file(...))`. This keeps secrets and environment identifiers out of HCL and makes the entire configuration portable across environments by swapping one file.

**2. Remote state — GCS backend**

```hcl
remote_state {
  backend = "gcs"
  config = {
    bucket = "${local.backend_bucket}"
    prefix = "terraform/state/${get_path_from_repo_root()}"
  }
  generate = {
    path      = "./backend.tf"
    if_exists = "overwrite_terragrunt"
  }
}
```

The `get_path_from_repo_root()` built-in automatically generates a unique, path-derived state prefix per Terragrunt unit (`terraform/state/runners/shared-cluster`, `terraform/state/runners/runner-L`, etc.) — no manual state path management required.

**3. Provider generation**

Both `google` and `google-beta` providers are code-generated into `providers.tf` at plan/apply time:

```hcl
generate "providers" {
  path      = "providers.tf"
  if_exists = "overwrite"
  contents  = <<-EOT
    provider "google" {
      project                     = var.project_id
      region                      = var.region
      impersonate_service_account = "${local.impersonate_sa}"
    }
    provider "google-beta" {
      project                     = var.project_id
      region                      = var.region
      impersonate_service_account = "${local.impersonate_sa}"
    }
  EOT
}
```

SA impersonation is injected directly into the provider config, so the CI runner never needs long-lived key credentials — it authenticates via WIF and impersonates the provisioning SA.

**4. Version pinning**

A `versions.tf` file is also generated, enforcing `terraform >= 1.7.4` and `hashicorp/google ~> 6.50` / `hashicorp/google-beta ~> 6.50` across all units.

-----

### Terragrunt Units

#### `runners/shared-cluster`

The foundational unit. Provisions the entire shared infrastructure by invoking the `shared-gke-resources` module. Its inputs define the complete network topology, IAM surface, and GKE cluster in one structured block:

- **VPC:** `runner-vpc` with subnet `gke-subnet` (`10.10.0.0/20`), secondary ranges for pods (`10.44.0.0/16`) and services (`10.48.0.0/20`).
- **Service Accounts:** Two SAs created dynamically:
  - `gke-nodes-sa` — node SA with logging and monitoring roles.
  - `gitlab-runner-project-sa` — runner SA with `roles/storage.objectUser` (cache bucket access) and a WIF binding granting `roles/iam.serviceAccountTokenCreator` to the Kubernetes service account principal `<project>.svc.id.goog[gitlab-runner/runner-sa]`.
- **GCS Cache Bucket:** `my-test-gitlab-runner-cache-bucket` in STANDARD class.
- **GKE Cluster:** `gitlab-cluster`, regional, with Workload Identity enabled, default node pool removed.

Outputs `gke_cluster_name` and `service_account_emails`, consumed by all runner node pool units via Terragrunt dependency blocks.

-----

#### `runners/runner-L`, `runners/runner-M`, `runners/runner-XL`

Each runner unit is a thin Terragrunt wrapper around the `node-pools` module. All three follow an identical pattern:

```hcl
dependency "cluster" {
  config_path = "../shared-cluster"

  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
  mock_outputs = {
    gke_cluster_name       = "mock-cluster-name"
    service_account_emails = { gitlab-nodes = "mock@gserviceaccount.com" }
  }
}
```

The `dependency` block wires each runner unit to `shared-cluster`’s outputs — cluster name and node SA email are passed in at runtime. Mock outputs allow `init`, `validate`, and `plan` to run without first applying the dependency, enabling independent CI validation.

**Runner sizing matrix:**

|Unit       |Node Pool Name|Machine Type    |Min/Max Nodes|Node Labels                            |
|-----------|--------------|----------------|-------------|---------------------------------------|
|`runner-L` |`runner-l`    |`n2-standard-2` |1 / 2        |`workload=gitlab-runner, size=runner-l`|
|`runner-M` |`runner-m`    |`e2-standard-2` |1 / 2        |`workload=gitlab-runner, size=runner-m`|
|`runner-XL`|`runner-xl`   |`n2d-standard-2`|1 / 2        |`workload=gitlab-runner, size=XL`      |

All node pools use `GKE_METADATA` workload metadata mode and carry the `runner-size=<pool-name>:NO_SCHEDULE` taint.

-----

## CI/CD Pipeline

The `runners/.gitlab-ci.yml` pipeline orchestrates Terragrunt operations. It is triggered manually (via web or pipeline trigger) on the default branch only, and exposes two runtime variables:

- **`WORK_DIR`** — selects the Terragrunt unit to operate on (`shared-cluster`, `runner-M`, `runner-L`, `runner-XL`).
- **`ACTION`** — selects the pipeline path (`apply` or `destroy`).

### Authentication — Workload Identity Federation

No static GCP credentials are stored in CI. Authentication uses GitLab’s OIDC token exchange:

```yaml
id_tokens:
  ID_TOKEN_GCP:
    aud: $CI_SERVER_URL
```

The `gcp_auth` job exchanges the OIDC token via `gcloud iam workload-identity-pools create-cred-config` against a pre-configured WIF pool/provider, generating a short-lived credential file (`_auth/cicd-credentials.json`). This file is passed as an artifact to all downstream jobs and sourced via `CLOUDSDK_AUTH_CREDENTIAL_FILE_OVERRIDE`.

The CI SA then impersonates the Terraform provisioning SA, as declared in the provider config generated by `root.hcl`.

### Pipeline Stages

|Stage     |Job       |Description                                                          |
|----------|----------|---------------------------------------------------------------------|
|`gcp_auth`|`gcp_auth`|WIF token exchange, credential file generation                       |
|`validate`|`validate`|`terragrunt run --all ... validate` + `hcl fmt`                      |
|`plan`    |`plan`    |`terragrunt run --all ... plan -out=plan.cache`                      |
|`deploy`  |`deploy`  |Manual gate — applies the saved plan                                 |
|`destroy` |`destroy` |Manual gate — destroys the selected unit (only when `ACTION=destroy`)|

The `--queue-include-dir "${WORK_DIR}/"` flag scopes each `terragrunt run --all` invocation to the selected unit, so the pipeline targets exactly one Terragrunt unit per run while still respecting the dependency graph.

-----

## Key Infrastructure Design Decisions

- **Terragrunt over raw Terraform** — root config inheritance, auto-generated backend/provider files, and `dependency` blocks eliminate boilerplate and enforce consistency across all units without duplicating provider or backend configuration.
- **Separation of shared vs. runner-specific state** — the shared cluster (VPC, GKE control plane, IAM) lives in its own state file, isolated from the ephemeral node pool states. Node pools can be destroyed and recreated independently.
- **SA impersonation over key-based auth** — no service account JSON keys exist in this project. The CI pipeline authenticates with WIF and impersonates the provisioning SA, following GCP’s recommended keyless authentication pattern.
- **Node pool taints for runner isolation** — each pool’s `NO_SCHEDULE` taint ensures workloads are only placed on the intended runner tier, preventing cross-contamination between runner sizes.
- **Mock outputs for CI safety** — all runner units define `mock_outputs` scoped to `["init", "validate", "plan"]`, allowing the full CI validation path to run without a live dependency apply.