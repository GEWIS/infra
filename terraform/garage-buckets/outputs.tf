output "buckets" {
  description = "Per bucket: Garage bucket ID, the OpenBao KV path holding its credentials, and the namespace allowed to read them."
  value = {
    for name, bucket in local.buckets : name => {
      bucket_id = garage_bucket.this[name].id
      kv_path   = "${vault_mount.garage.path}/${bucket.namespace}/${name}"
      namespace = bucket.namespace
      bao_role  = vault_kubernetes_auth_backend_role.namespace[bucket.namespace].role_name
    }
  }
}
