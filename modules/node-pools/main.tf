resource "google_container_node_pool" "node_pool" {
  project    = var.project_id
  name       = var.node_pool.name
  location   = var.node_pool.location
  cluster    = var.node_pool.cluster_name
  node_count = var.node_pool.initial_node_count
  autoscaling {
    min_node_count = var.node_pool.min_node_count
    max_node_count = var.node_pool.max_node_count
  }

  node_config {
    machine_type = var.node_pool.machine_type

    service_account = var.node_pool.service_account
    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]

    workload_metadata_config {
      mode = var.node_pool.workload_metadata_config_mode
    }
  }
}