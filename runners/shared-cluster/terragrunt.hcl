include {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "../../modules/shared-gke-resources"
}

locals {
  project_id          = "my-test-project-88"
  region              = "europe-west1"
  namespace           = "gitlab-runner"
  k8s_service_account = "runner-sa"
}

inputs = {
  project_id = local.project_id
  region     = local.region

  vpc_network = {
    name = "runner-vpc"

    subnets = [
      {
        name          = "gke-subnet"
        region        = local.region
        ip_cidr_range = "10.10.0.0/20"
        secondary_ip_ranges = {
          gke-gitlab-cluster-pods     = "10.44.0.0/16"
          gke-gitlab-cluster-services = "10.48.0.0/20"
        }
      }
    ]
  }

  storage_buckets = {
    gitlab-cache-bucket = {
      name          = "my-test-gitlab-runner-cache-bucket"
      location      = local.region
      storage_class = "STANDARD"
      force_destroy = true
    }
  }

  service_accounts = {
    gitlab-nodes = {
      name = "gke-nodes-sa"
      iam_project_roles = [
        "roles/logging.logWriter",
        "roles/monitoring.metricWriter",
        "roles/monitoring.viewer",
      ]
    }
    gitlab-runner-project-sa = {
      name = "gitlab-runner-project-sa"
      iam = {
        "serviceAccount:${local.project_id}.svc.id.goog[${local.namespace}/${local.k8s_service_account}]" = ["roles/iam.serviceAccountTokenCreator"]
      }
      iam_project_roles = [
        "roles/storage.objectUser",
      ]
    }
  }

  gke_cluster = {
    name                     = "gitlab-cluster"
    location                 = local.region
    remove_default_node_pool = true
    initial_node_count       = 1
    deletion_protection      = false
    subnetwork_key           = "gke-subnet"
    secondary_range_names = {
      pods     = "gke-gitlab-cluster-pods"
      services = "gke-gitlab-cluster-services"
    }
    workload_identity_config = true
  }

}