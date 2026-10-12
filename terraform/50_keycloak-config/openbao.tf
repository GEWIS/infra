resource "vault_mount" "keycloak" {
  path        = "keycloak"
  type        = "kv-v2"
  description = "Keycloak client credentials, one path per consuming namespace."
}

resource "vault_kubernetes_auth_backend_role" "namespace" {
  for_each = local.namespace_policies

  backend   = "kubernetes"
  role_name = "keycloak-${each.key}"

  bound_service_account_names      = ["*"]
  bound_service_account_namespaces = [each.key]

  token_policies = each.value
  token_ttl      = 3600
}

moved {
  from = vault_kubernetes_auth_backend_role.forward_auth_namespace
  to   = vault_kubernetes_auth_backend_role.namespace
}
