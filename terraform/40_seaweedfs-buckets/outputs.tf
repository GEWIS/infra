output "buckets" {
  description = "Per bucket: the SeaweedFS bucket ARN, the OpenBao KV path holding its credentials, the namespace allowed to read them, and whether s3-01 copies it off-site."
  value = {
    for name, bucket in local.buckets : name => {
      bucket_arn = aws_s3_bucket.this[name].arn
      kv_path    = "${vault_mount.seaweedfs.path}/${bucket.namespace}/${name}"
      namespace  = bucket.namespace
      bao_role   = vault_kubernetes_auth_backend_role.namespace[bucket.namespace].role_name
      backup     = !try(bucket.no_backup, false)
    }
  }
}
