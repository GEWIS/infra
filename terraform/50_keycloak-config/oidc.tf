resource "random_password" "oidc_client_secret" {
  for_each = local.oidc_clients

  length  = 64
  special = false
}

resource "keycloak_openid_client" "oidc" {
  for_each = local.oidc_clients

  realm_id      = local.realm
  client_id     = each.value.client_id
  name          = each.key
  description   = "Managed by OpenTofu in GEWIS/infra, terraform/50_keycloak-config. Changes made here are overwritten."
  access_type   = "CONFIDENTIAL"
  client_secret = random_password.oidc_client_secret[each.key].result

  standard_flow_enabled        = true
  implicit_flow_enabled        = false
  direct_access_grants_enabled = false
  service_accounts_enabled     = false

  valid_redirect_uris = each.value.redirect_uris
}

resource "keycloak_openid_client_default_scopes" "oidc" {
  for_each = local.oidc_clients

  realm_id  = local.realm
  client_id = keycloak_openid_client.oidc[each.key].id

  default_scopes = ["acr", "basic", "email", "profile", "roles", "web-origins"]
}

resource "keycloak_openid_group_membership_protocol_mapper" "oidc_groups" {
  for_each = local.oidc_clients

  realm_id  = local.realm
  client_id = keycloak_openid_client.oidc[each.key].id
  name      = "groups"

  claim_name          = "groups"
  full_path           = false
  add_to_id_token     = true
  add_to_access_token = true
  add_to_userinfo     = true
}

resource "keycloak_openid_user_client_role_protocol_mapper" "grafana_roles" {
  realm_id  = local.realm
  client_id = keycloak_openid_client.oidc["grafana"].id
  name      = "client roles"

  claim_name                  = "roles"
  client_id_for_role_mappings = keycloak_openid_client.oidc["grafana"].client_id
  multivalued                 = true
  add_to_id_token             = true
  add_to_access_token         = true
  add_to_userinfo             = true
}

resource "vault_kv_secret_v2" "oidc_client" {
  for_each = local.oidc_clients

  mount = vault_mount.keycloak.path
  name  = "${each.value.namespace}/${each.key}"

  data_json = jsonencode({
    client_id     = keycloak_openid_client.oidc[each.key].client_id
    client_secret = random_password.oidc_client_secret[each.key].result
  })
}

resource "vault_policy" "oidc_client_read" {
  for_each = local.oidc_clients

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
