resource "random_password" "client_secret" {
  for_each = local.forward_auth_clients

  length  = 64
  special = false
}

resource "random_password" "plugin_secret" {
  for_each = local.forward_auth_clients

  length  = 32
  special = false
}

resource "keycloak_openid_client" "forward_auth" {
  for_each = local.forward_auth_clients

  realm_id      = local.realm
  client_id     = each.key
  name          = each.key
  description   = "Managed by OpenTofu in GEWIS/infra, terraform/50_keycloak-config. Changes made here are overwritten."
  access_type   = "CONFIDENTIAL"
  client_secret = random_password.client_secret[each.key].result

  standard_flow_enabled        = true
  implicit_flow_enabled        = false
  direct_access_grants_enabled = false
  service_accounts_enabled     = false

  valid_redirect_uris = each.value.redirect_uris
}

resource "keycloak_openid_group_membership_protocol_mapper" "groups" {
  for_each = local.forward_auth_clients

  realm_id  = local.realm
  client_id = keycloak_openid_client.forward_auth[each.key].id
  name      = "groups"

  claim_name          = "groups"
  full_path           = false
  add_to_id_token     = true
  add_to_access_token = true
  add_to_userinfo     = true
}

resource "vault_mount" "keycloak" {
  path        = "keycloak"
  type        = "kv-v2"
  description = "Forward-auth client credentials, one path per consuming namespace."
}

resource "vault_kv_secret_v2" "forward_auth_client" {
  for_each = local.forward_auth_clients

  mount = vault_mount.keycloak.path
  name  = "${each.value.namespace}/${each.key}"

  data_json = jsonencode({
    client_id            = keycloak_openid_client.forward_auth[each.key].client_id
    providerClientSecret = random_password.client_secret[each.key].result
    pluginSecret         = random_password.plugin_secret[each.key].result
  })
}

resource "vault_policy" "forward_auth_client_read" {
  for_each = local.forward_auth_clients

  name = "keycloak-${each.value.namespace}-${each.key}"

  policy = <<-EOT
    path "${vault_mount.keycloak.path}/data/${each.value.namespace}/${each.key}" {
      capabilities = ["read"]
    }

    path "${vault_mount.keycloak.path}/metadata/${each.value.namespace}/${each.key}" {
      capabilities = ["read"]
    }
  EOT
}

resource "vault_kubernetes_auth_backend_role" "forward_auth_namespace" {
  for_each = local.forward_auth_namespace_policies

  backend   = "kubernetes"
  role_name = "keycloak-${each.key}"

  bound_service_account_names      = ["*"]
  bound_service_account_namespaces = [each.key]

  token_policies = each.value
  token_ttl      = 3600
}
