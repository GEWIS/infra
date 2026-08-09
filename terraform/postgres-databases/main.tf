locals {
  cluster_namespace = "postgres"
  cluster_host      = "postgres-rw.postgres.svc.cluster.local"

  databases = {
    authentik = { namespace = "authentik" }
  }

  consumer_namespaces = toset([for database in local.databases : database.namespace])

  namespace_policies = {
    for namespace in local.consumer_namespaces : namespace => [
      for name, database in local.databases :
      vault_policy.database_read[name].name if database.namespace == namespace
    ]
  }
}

resource "random_password" "role" {
  for_each = local.databases

  length  = 32
  special = false
}

resource "vault_mount" "postgres" {
  path        = "postgres"
  type        = "kv-v2"
  description = "Postgres role credentials, one path per consuming namespace."
}

resource "vault_kv_secret_v2" "credentials" {
  for_each = local.databases

  mount = vault_mount.postgres.path
  name  = "${each.value.namespace}/${each.key}"

  data_json = jsonencode({
    username = each.key
    password = random_password.role[each.key].result
    dbname   = each.key
    host     = local.cluster_host
    port     = "5432"
  })
}

resource "vault_policy" "database_read" {
  for_each = local.databases

  name = "postgres-${each.value.namespace}-${each.key}"

  policy = <<-EOT
    path "${vault_mount.postgres.path}/data/${each.value.namespace}/${each.key}" {
      capabilities = ["read"]
    }

    path "${vault_mount.postgres.path}/metadata/${each.value.namespace}/${each.key}" {
      capabilities = ["read"]
    }
  EOT
}

resource "vault_kubernetes_auth_backend_role" "consumer" {
  for_each = local.namespace_policies

  backend   = "kubernetes"
  role_name = "postgres-${each.key}"

  bound_service_account_names      = ["*"]
  bound_service_account_namespaces = [each.key]

  token_policies = each.value
  token_ttl      = 3600
}

resource "vault_kubernetes_auth_backend_role" "cluster" {
  backend   = "kubernetes"
  role_name = "postgres-cluster"

  bound_service_account_names      = ["*"]
  bound_service_account_namespaces = [local.cluster_namespace]

  token_policies = [for policy in vault_policy.database_read : policy.name]
  token_ttl      = 3600
}
