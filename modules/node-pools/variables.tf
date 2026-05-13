variable "project_id" {
  type = string
}

variable "region" {
  type = string
}

variable "node_pool" {
  type = object({
    name                          = string
    location                      = string
    cluster_name                  = string
    initial_node_count            = number
    min_node_count                = optional(number, 1)
    max_node_count                = optional(number, 2)
    machine_type                  = string
    service_account               = string
    workload_metadata_config_mode = optional(string, "GKE_METADATA")
  })

  validation {
    condition = contains([
      "e2-standard-2",
      "n2-standard-2",
      "n2d-standard-2"
    ], var.node_pool.machine_type)

    error_message = "Allowed machine types: e2-standard-2, n2-standard-2, n2d-standard-2."
  }
}