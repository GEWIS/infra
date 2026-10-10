output "postgres" {
  description = "Per Postgres database: the OpenBao KV path holding its role credentials, the namespace allowed to read them, and the OpenBao role that namespace logs in as."
  value = {
    for name, database in local.postgres_databases : name => {
      kv_path   = "${vault_mount.postgres.path}/${database.namespace}/${name}"
      namespace = database.namespace
      bao_role  = vault_kubernetes_auth_backend_role.postgres[database.namespace].role_name
    }
  }
}

output "mariadb" {
  description = "Per MariaDB database: the OpenBao KV path holding its user credentials, the namespace allowed to read them, and the OpenBao role that namespace logs in as."
  value = {
    for name, database in local.mariadb_databases : name => {
      kv_path   = "${vault_mount.mariadb.path}/${database.namespace}/${name}"
      namespace = database.namespace
      bao_role  = vault_kubernetes_auth_backend_role.mariadb[database.namespace].role_name
    }
  }
}
