variable "project_id" {

}

variable "region" {
  default = "europe-west1"
}

variable "namespace" {
  default = "gitlab-runner"
}

variable "k8s_service_account" {
  default = "runner-sa"
}

variable "gcp_project_sa" {
  default = "gitlab-runner-sa"
}

variable "machine_type" {
  default = "n2d-standard-2"
}

variable "gcs_cache_suffix" {
  default = "gitlab-runner-cache-bucket"
}