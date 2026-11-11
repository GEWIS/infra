locals {
  s3_endpoint = "https://s3.gewis.nl"
  s3_region   = "us-east-1"

  # Every bucket is copied off-site to Scaleway by seaweedfs-backup on s3-01 unless
  # it sets no_backup = true, which becomes the bucket tag no_backup=true that the
  # host reads. See docs/seaweedfs-backup/. Observability data rebuilds by
  # accrual and zot's images are pushed again from CI, so both opt out.
  #
  # backup_class picks the Scaleway storage class of a bucket's copy (STANDARD or
  # GLACIER; unset is STANDARD) and becomes the tag backup_class.
  # The database archives stay STANDARD: recovery reads them in place. Nextcloud
  # is bulk files nothing reads until a full restore, so it goes to Glacier.
  #
  # backup_encrypt = true copies the bucket through rclone crypt, so Scaleway
  # only holds ciphertext; it becomes the tag backup_encrypt=true. For user
  # files only: the database archives must stay readable to Barman and
  # mariadb-operator in place.
  buckets = {
    loki       = { namespace = "observability", no_backup = true }
    mimir      = { namespace = "observability", no_backup = true }
    tempo      = { namespace = "observability", no_backup = true }
    postgres   = { namespace = "postgres" }
    mariadb    = { namespace = "mariadb" }
    kaneo      = { namespace = "kaneo-prod" }
    nextcloud  = { namespace = "nextcloud-prod", backup_class = "GLACIER", backup_encrypt = true }
    mattermost = { namespace = "mattermost-prod", backup_encrypt = true }
    zot        = { namespace = "zot-prod", no_backup = true }
  }

  # The one place each default lives; the tags and the output read these.
  no_backup      = { for name, bucket in local.buckets : name => try(bucket.no_backup, false) }
  backup_class   = { for name, bucket in local.buckets : name => try(bucket.backup_class, null) }
  backup_encrypt = { for name, bucket in local.buckets : name => try(bucket.backup_encrypt, false) }

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
  tags = merge(
    local.no_backup[each.key] ? { no_backup = "true" } : {},
    local.backup_class[each.key] != null ? { backup_class = local.backup_class[each.key] } : {},
    local.backup_encrypt[each.key] ? { backup_encrypt = "true" } : {},
  )
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

  # Object, list and multipart operations only. s3:* would map to SeaweedFS's
  # Admin action, which also lets an app retag its bucket (no_backup=true drops
  # it from the off-site copy without any alert) or delete it.
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject",
        "s3:ListBucket",
        "s3:GetBucketLocation",
        "s3:ListMultipartUploads",
        "s3:ListParts",
        "s3:AbortMultipartUpload",
      ]
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
