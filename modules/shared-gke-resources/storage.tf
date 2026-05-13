locals {
  bucket_iam = merge([
    for bucket_key, bucket in var.storage_buckets : {
      for role, members in coalesce(bucket.iam, {}) :
      "${bucket_key}-${role}" => {
        bucket  = bucket_key
        role    = role
        members = members
      }
    }
  ]...)
}

resource "google_storage_bucket" "bucket" {
  for_each = var.storage_buckets

  name          = each.value.name
  location      = each.value.location
  force_destroy = each.value.force_destroy
  versioning {
    enabled = each.value.versioning
  }
}

resource "google_storage_bucket_iam_binding" "binding" {
  for_each = local.bucket_iam

  bucket  = google_storage_bucket.bucket[each.value.bucket].name
  role    = each.value.role
  members = each.value.members
}