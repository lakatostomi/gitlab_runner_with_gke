include {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "git::https://gitlab.com/terraform_projects2/gke-runner-modules.git//node-pools?ref=v1.0.0"
}

dependency "cluster" {
  config_path = "../shared-cluster"

  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
  mock_outputs = {
    gke_cluster_name = "mock-cluster-name"
    service_account_emails = {
      gitlab-nodes = "mock@gserviceaccount.com"
    }
  }
}

inputs = {
  project_id = "my-test-project-88"
  region     = "europe-west1"

  node_pool = {
    name               = "runner-xl"
    location           = "europe-west1"
    cluster_name       = dependency.cluster.outputs.gke_cluster_name
    initial_node_count = 1
    min_node_count     = 1
    max_node_count     = 2
    labels             = {workload = "gitlab-runner", size = "XL"}
    machine_type       = "n2d-standard-2"
    service_account    = dependency.cluster.outputs.service_account_emails["gitlab-nodes"]
  }
}