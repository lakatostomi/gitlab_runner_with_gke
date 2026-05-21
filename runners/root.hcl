locals {
  config = yamldecode(file("config.yaml"))

  project_id     = lookup(local.config.inputs, "project_id")
  region         = lookup(local.config.inputs, "region")
  backend_bucket = lookup(local.config.inputs, "backend_bucket")
  impersonate_sa = lookup(local.config.inputs, "impersonate_sa")
}

inputs = {
  project_id = local.project_id
  region     = local.region
}

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

generate "providers" {
  path      = "providers.tf"
  if_exists = "overwrite"
  contents  = <<-EOT
    provider "google" {
        project = var.project_id
        region = var.region
        impersonate_service_account = "${local.impersonate_sa}"
    }
    provider "google-beta" {
        project = var.project_id
        region = var.region
        impersonate_service_account = "${local.impersonate_sa}"
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