remote_state {
  backend = "gcs"
  config = {
    bucket = "tf-state-bucket-for-wif-test-project"
    prefix = "terraform/state/${get_path_from_repo_root()}"
  }
  generate = {
    path      = "./backend.tf"
    if_exists = "overwrite_terragrunt"
  }
}

generate "providers" {
  path      = "providers.tf"
  if_exists = "overwrite"
  contents  = <<-EOT
    provider "google" {
        project = var.project_id
        region = var.region
        impersonate_service_account = "iac-deploy-sa@my-test-project-88.iam.gserviceaccount.com"
    }
    provider "google-beta" {
        project = var.project_id
        region = var.region
        impersonate_service_account = "iac-deploy-sa@my-test-project-88.iam.gserviceaccount.com"
    }
    EOT
}

generate "versions" {
  path      = "versions.tf"
  if_exists = "overwrite"
  contents  = <<-EOT
    terraform {
        required_version = ">= 1.7.4"
      required_providers {
        google = {
          source = "hashicorp/google"
          version = "~> 6.50"
        }
        google-beta = {
          source = "hashicorp/google-beta"
          version = "~> 6.50"
        }
      }
    }
    EOT
}