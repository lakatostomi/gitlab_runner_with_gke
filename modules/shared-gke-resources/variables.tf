variable "project_id" {
  type = string
}

variable "region" {
  type = string
}

variable "vpc_network" {
  type = object({
    name                    = string
    auto_create_subnetworks = optional(bool, false)
    subnets = list(object({
      name                = string
      region              = string
      ip_cidr_range       = string
      secondary_ip_ranges = optional(map(string), {})
    }))
  })
}

variable "storage_buckets" {
  type = map(object({
    name          = string
    location      = string
    versioning    = optional(bool, false)
    force_destroy = bool
    uniform_bucket_level_access = optional(bool, false)
    iam           = optional(map(string))
  }))
}

variable "service_accounts" {
  type = map(object({
    name              = string
    iam_project_roles = optional(list(string))
    iam               = optional(map(list(string)))
  }))
  validation {
    condition = alltrue(flatten([
      for sa in var.service_accounts : [
        for principal in keys(coalesce(sa.iam, {})) :
        can(regex("^(serviceAccount|user|group):", principal))
      ]
    ]))
    error_message = "Service account IAM principals must start with serviceAccount:, user:, or group:."
  }
}

variable "gke_cluster" {
  type = object({
    name                     = string
    location                 = string
    remove_default_node_pool = bool
    initial_node_count       = number
    deletion_protection      = bool
    subnetwork_key           = string
    secondary_range_names = object({
      pods     = string
      services = string
    })
    workload_identity_config = optional(bool, true)
  })
}
