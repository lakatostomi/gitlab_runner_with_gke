resource "google_compute_network" "vpc_network" {
  project                 = var.project_id
  name                    = var.vpc_network.name
  auto_create_subnetworks = var.vpc_network.auto_create_subnetworks
  mtu                     = 1460
}

resource "google_compute_subnetwork" "subnets" {
  for_each = {
    for subnet in var.vpc_network.subnets : subnet.name => subnet
  }

  project       = var.project_id
  name          = each.value.name
  ip_cidr_range = each.value.ip_cidr_range
  region        = each.value.region
  network       = google_compute_network.vpc_network.id

  dynamic "secondary_ip_range" {
    for_each = each.value.secondary_ip_ranges
    content {
      range_name    = secondary_ip_range.key
      ip_cidr_range = secondary_ip_range.value
    }
  }
}