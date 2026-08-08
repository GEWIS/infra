locals {
  s3_endpoint = "http://10.82.50.100:3900"
  s3_region   = "garage"

  buckets = {
    loki  = { size_gib = 20, namespace = "monitoring" }
    mimir = { size_gib = 20, namespace = "monitoring" }
    tempo = { size_gib = 10, namespace = "monitoring" }
  }

  namespaces = toset([for bucket in local.buckets : bucket.namespace])

  namespace_policies = {
    for namespace in local.namespaces : namespace => [
      for name, bucket in local.buckets :
      vault_policy.bucket_read[name].name if bucket.namespace == namespace
    ]
  }
}

resource "garage_bucket" "this" {
  for_each = local.buckets

  global_alias = each.key
  max_size     = each.value.size_gib * 1024 * 1024 * 1024
}

resource "garage_key" "this" {
  for_each = local.buckets

  name          = "${each.value.namespace}-${each.key}"
  never_expires = true
}

resource "garage_bucket_permission" "this" {
  for_each = local.buckets

  bucket_id     = garage_bucket.this[each.key].id
  access_key_id = garage_key.this[each.key].id
  read          = true
  write         = true
  owner         = false
}

resource "vault_mount" "garage" {
  path        = "garage"
  type        = "kv-v2"
  description = "Garage S3 credentials, one path per consuming namespace."
}

resource "vault_kv_secret_v2" "credentials" {
  for_each = local.buckets

  mount = vault_mount.garage.path
  name  = "${each.value.namespace}/${each.key}"

  data_json = jsonencode({
    bucket            = each.key
    endpoint          = local.s3_endpoint
    region            = local.s3_region
    access_key_id     = garage_key.this[each.key].id
    secret_access_key = garage_key.this[each.key].secret_access_key
  })
}

resource "vault_policy" "bucket_read" {
  for_each = local.buckets

  name = "garage-${each.value.namespace}-${each.key}"

  policy = <<-EOT
    path "${vault_mount.garage.path}/data/${each.value.namespace}/${each.key}" {
      capabilities = ["read"]
    }

    path "${vault_mount.garage.path}/metadata/${each.value.namespace}/${each.key}" {
      capabilities = ["read"]
    }
  EOT
}

resource "vault_kubernetes_auth_backend_role" "namespace" {
  for_each = local.namespace_policies

  backend   = "kubernetes"
  role_name = "garage-${each.key}"

  bound_service_account_names      = ["*"]
  bound_service_account_namespaces = [each.key]

  token_policies = each.value
  token_ttl      = 3600
}
