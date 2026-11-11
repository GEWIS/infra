output "buckets" {
  description = "Per bucket: the SeaweedFS bucket ARN, the OpenBao KV path holding its credentials, the namespace allowed to read them, whether s3-01 copies it off-site, the Scaleway storage class it sets for that copy (null: the job's default, STANDARD), and whether that copy is encrypted with rclone crypt."
  value = {
    for name, bucket in local.buckets : name => {
      bucket_arn     = aws_s3_bucket.this[name].arn
      kv_path        = "${vault_mount.seaweedfs.path}/${bucket.namespace}/${name}"
      namespace      = bucket.namespace
      bao_role       = vault_kubernetes_auth_backend_role.namespace[bucket.namespace].role_name
      backup         = !local.no_backup[name]
      backup_class   = local.backup_class[name]
      backup_encrypt = local.backup_encrypt[name]
    }
  }
}
