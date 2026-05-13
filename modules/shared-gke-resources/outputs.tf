output "gke_cluster_name" {
  value = google_container_cluster.gke_cluster.name
}

output "service_account_emails" {
  description = "Emails of created service accounts"
  value       = local.service_accounts
}