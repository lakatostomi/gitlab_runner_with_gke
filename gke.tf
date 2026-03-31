locals {
  subnet_name       = "runner-subnet"
  primary_ip4_range = "10.10.0.0/24"
  gke_pods_range    = "10.44.0.0/14"
  gke_service_range = "10.48.0.0/20"
  list_of_apis      = ["compute.googleapis.com", "container.googleapis.com", "iam.googleapis.com", "iamcredentials.googleapis.com", "cloudresourcemanager.googleapis.com", "storage.googleapis.com", "monitoring.googleapis.com", "logging.googleapis.com"]
}

resource "google_project_service" "enable_apis" {
  for_each = toset(local.list_of_apis)
  project  = var.project_id
  service  = each.key
}

module "gitlab_vpc" {
  source                   = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/net-vpc?ref=v40.0.0"
  project_id               = var.project_id
  name                     = "gitlab-runner-vpc"
  auto_create_subnetworks  = false
  create_googleapis_routes = null
  subnets = [
    {
      ip_cidr_range = local.primary_ip4_range
      name          = local.subnet_name
      region        = var.region
      secondary_ip_ranges = {
        gke-gitlab-cluster-pods     = local.gke_pods_range
        gke-gitlab-cluster-services = local.gke_service_range
      }
    },
  ]
}

module "gitlab-cache-bucket" {
  source     = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/gcs?ref=v40.0.0"
  project_id = var.project_id

  name          = "${var.project_id}-${var.gcs_cache_suffix}"
  storage_class = "STANDARD"
  location      = var.region
  force_destroy = true

  iam = {
    "roles/storage.objectUser" = ["serviceAccount:${module.gitlab-runner-sa.email}"]
  }

  versioning = false

}

module "gitlab-cluster-sa" {
  source     = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/iam-service-account?ref=v40.0.0"
  project_id = var.project_id
  name       = "gke-cluster-sa"

  iam_project_roles = {
    "${var.project_id}" = [
      "roles/logging.logWriter",
      "roles/monitoring.metricWriter",
      "roles/monitoring.viewer",
    ]
  }
}

module "gitlab-runner-sa" {
  source     = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/iam-service-account?ref=v40.0.0"
  project_id = var.project_id
  name       = var.gcp_project_sa

  iam = {
    "roles/iam.serviceAccountTokenCreator" = [
      "serviceAccount:${var.project_id}.svc.id.goog[${var.namespace}/${var.k8s_service_account}]",
    ]
  }

  iam_project_roles = {}
}

resource "google_container_cluster" "gitlab_cluster" {
  name     = "gitlab-cluster"
  location = var.region

  remove_default_node_pool = true
  initial_node_count       = 1
  deletion_protection      = false
  network                  = module.gitlab_vpc.self_link
  subnetwork               = module.gitlab_vpc.subnet_self_links["${var.region}/${local.subnet_name}"]
  ip_allocation_policy {
    cluster_secondary_range_name  = "gke-gitlab-cluster-pods"
    services_secondary_range_name = "gke-gitlab-cluster-services"
  }

  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

}

resource "google_container_node_pool" "cluster_node" {
  name       = "gitlab-node-pool"
  location   = var.region
  cluster    = google_container_cluster.gitlab_cluster.name
  node_count = 1
  autoscaling {
    min_node_count = 1
    max_node_count = 2
  }

  node_config {
    machine_type = var.machine_type

    service_account = module.gitlab-cluster-sa.email
    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]

    workload_metadata_config {
      mode = "GKE_METADATA"
    }
  }
}