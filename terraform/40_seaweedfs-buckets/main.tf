locals {
  s3_endpoint = "http://s3.net.gewis.nl:8333"
  s3_region   = "us-east-1"

  buckets = {
    loki     = { namespace = "observability" }
    mimir    = { namespace = "observability" }
    tempo    = { namespace = "observability" }
    postgres = { namespace = "postgres" }
    mariadb  = { namespace = "mariadb" }
  }

  namespaces = toset([for bucket in local.buckets : bucket.namespace])

  namespace_policies = {
    for namespace in local.namespaces : namespace => [
      for name, bucket in local.buckets :
      vault_policy.bucket_read[name].name if bucket.namespace == namespace
    ]
  }
}

resource "aws_s3_bucket" "this" {
  for_each = local.buckets

  bucket = each.key
}

resource "aws_iam_user" "this" {
  for_each = local.buckets

  name = "${each.value.namespace}-${each.key}"
}

resource "aws_iam_access_key" "this" {
  for_each = local.buckets

  user = aws_iam_user.this[each.key].name
}

resource "aws_iam_user_policy" "this" {
  for_each = local.buckets

  name = "${each.key}-read-write"
  user = aws_iam_user.this[each.key].name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = ["s3:*"]
      Resource = [
        aws_s3_bucket.this[each.key].arn,
        "${aws_s3_bucket.this[each.key].arn}/*",
      ]
    }]
  })
}

resource "vault_mount" "seaweedfs" {
  path        = "seaweedfs"
  type        = "kv-v2"
  description = "SeaweedFS S3 credentials, one path per consuming namespace."
}

resource "vault_kv_secret_v2" "credentials" {
  for_each = local.buckets

  mount = vault_mount.seaweedfs.path
  name  = "${each.value.namespace}/${each.key}"

  data_json = jsonencode({
    bucket            = each.key
    endpoint          = local.s3_endpoint
    region            = local.s3_region
    access_key_id     = aws_iam_access_key.this[each.key].id
    secret_access_key = aws_iam_access_key.this[each.key].secret
  })
}

resource "vault_policy" "bucket_read" {
  for_each = local.buckets

  name = "seaweedfs-${each.value.namespace}-${each.key}"

  policy = <<-EOT
    path "${vault_mount.seaweedfs.path}/data/${each.value.namespace}/${each.key}" {
      capabilities = ["read"]
    }

    path "${vault_mount.seaweedfs.path}/metadata/${each.value.namespace}/${each.key}" {
      capabilities = ["read"]
    }
  EOT
}

resource "vault_kubernetes_auth_backend_role" "namespace" {
  for_each = local.namespace_policies

  backend   = "kubernetes"
  role_name = "seaweedfs-${each.key}"

  bound_service_account_names      = ["*"]
  bound_service_account_namespaces = [each.key]

  token_policies = each.value
  token_ttl      = 3600
}
