locals {
  project_roles = merge([
    for sa_key, sa in var.service_accounts : {
      for role in coalesce(sa.iam_project_roles, []) :
      "${sa_key}-${role}" => {
        sa    = sa_key
        roles = role
      }
    }
  ]...)

  iam_roles = merge([
    for sa_key, sa in var.service_accounts : {
      for principal, roles in coalesce(sa.iam, {}) :
      "${sa_key}-${principal}" => {
        sa        = sa_key
        principal = principal
        roles     = roles
      }
    }
  ]...)

  sa_iam_role = merge([
    for key, item in local.iam_roles : {
      for role in item.roles :
      "${item.principal}-${role}" => {
        sa        = item.sa
        principal = item.principal
        role      = role
      }
    }
  ]...)

  service_accounts = {
    for key, sa in google_service_account.service_account :
    key => sa.email
  }
}

resource "google_service_account" "service_account" {
  for_each     = var.service_accounts
  project      = var.project_id
  account_id   = each.value.name
  display_name = each.key
}

resource "google_project_iam_member" "service_account_iam_role" {
  for_each = local.project_roles
  project  = var.project_id
  role     = each.value.roles
  member   = "serviceAccount:${google_service_account.service_account[each.value.sa].email}"
}

resource "google_service_account_iam_member" "service_account_iam_member" {
  for_each           = local.sa_iam_role
  service_account_id = google_service_account.service_account[each.value.sa].name
  role               = each.value.role
  member             = each.value.principal
}