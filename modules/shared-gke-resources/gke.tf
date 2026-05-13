resource "google_container_cluster" "gke_cluster" {
  project  = var.project_id
  name     = var.gke_cluster.name
  location = var.gke_cluster.location

  remove_default_node_pool = var.gke_cluster.remove_default_node_pool
  initial_node_count       = var.gke_cluster.initial_node_count
  deletion_protection      = var.gke_cluster.deletion_protection
  network                  = google_compute_network.vpc_network.self_link
  subnetwork               = google_compute_subnetwork.subnets["${var.gke_cluster.subnetwork_key}"].self_link
  ip_allocation_policy {
    cluster_secondary_range_name  = var.gke_cluster.secondary_range_names.pods
    services_secondary_range_name = var.gke_cluster.secondary_range_names.services
  }

  release_channel {
    channel = "REGULAR"
  }

  dynamic "workload_identity_config" {
    for_each = var.gke_cluster.workload_identity_config ? [1] : []
    content {
      workload_pool = "${var.project_id}.svc.id.goog"
    }
  }
}