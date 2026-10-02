output "databases" {
  description = "Per database: the OpenBao KV path holding its role credentials, the namespace allowed to read them, and the OpenBao role that namespace logs in as."
  value = {
    for name, database in local.databases : name => {
      kv_path   = "${vault_mount.postgres.path}/${database.namespace}/${name}"
      namespace = database.namespace
      bao_role  = vault_kubernetes_auth_backend_role.consumer[database.namespace].role_name
    }
  }
}
