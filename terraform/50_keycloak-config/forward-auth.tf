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

resource "keycloak_openid_client_default_scopes" "forward_auth" {
  for_each = local.forward_auth_clients

  realm_id  = local.realm
  client_id = keycloak_openid_client.forward_auth[each.key].id

  default_scopes = ["acr", "basic", "client-roles", "email", "profile", "roles", "web-origins"]
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

resource "keycloak_openid_audience_protocol_mapper" "audience" {
  for_each = local.forward_auth_clients

  realm_id  = local.realm
  client_id = keycloak_openid_client.forward_auth[each.key].id
  name      = "audience"

  included_client_audience = keycloak_openid_client.forward_auth[each.key].client_id
  add_to_id_token          = false
  add_to_access_token      = true
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

