locals {
  oidc_clients = {
    grafana = {
      display_name  = "Grafana"
      namespace     = "observability"
      launch_url    = "https://grafana.cbc.gewis.nl:8443/"
      redirect_uris = ["https://grafana.cbc.gewis.nl:8443/login/generic_oauth"]
    }
  }

  oidc_namespaces = toset([for client in local.oidc_clients : client.namespace])

  oidc_namespace_policies = {
    for namespace in local.oidc_namespaces : namespace => [
      for name, client in local.oidc_clients :
      vault_policy.oidc_client_read[name].name if client.namespace == namespace
    ]
  }
}

data "authentik_flow" "authorization" {
  slug = "default-provider-authorization-implicit-consent"
}

data "authentik_flow" "invalidation" {
  slug = "default-provider-invalidation-flow"
}

data "authentik_certificate_key_pair" "signing" {
  name = "authentik Self-signed Certificate"
}

data "authentik_property_mapping_provider_scope" "oidc" {
  managed_list = [
    "goauthentik.io/providers/oauth2/scope-openid",
    "goauthentik.io/providers/oauth2/scope-email",
    "goauthentik.io/providers/oauth2/scope-offline_access",
  ]
}

resource "authentik_property_mapping_provider_scope" "profile" {
  name        = "GEWISWG: profile with directory groups"
  scope_name  = "profile"
  description = "General Profile Information"
  expression  = <<-EOT
    return {
        "name": request.user.name,
        "given_name": request.user.name,
        "preferred_username": request.user.username,
        "nickname": request.user.username,
        "groups": request.user.attributes.get("groups", []),
    }
  EOT
}

resource "random_password" "oidc_client_secret" {
  for_each = local.oidc_clients

  length  = 64
  special = false
}

resource "authentik_provider_oauth2" "client" {
  for_each = local.oidc_clients

  name          = each.key
  client_id     = each.key
  client_secret = random_password.oidc_client_secret[each.key].result
  client_type   = "confidential"

  authorization_flow = data.authentik_flow.authorization.id
  invalidation_flow  = data.authentik_flow.invalidation.id
  signing_key        = data.authentik_certificate_key_pair.signing.id
  grant_types        = ["authorization_code", "refresh_token"]

  property_mappings = concat(
    data.authentik_property_mapping_provider_scope.oidc.ids,
    [authentik_property_mapping_provider_scope.profile.id],
  )

  allowed_redirect_uris = [
    for url in each.value.redirect_uris : {
      matching_mode = "strict"
      url           = url
    }
  ]
}

resource "authentik_application" "client" {
  for_each = local.oidc_clients

  name              = each.value.display_name
  slug              = each.key
  protocol_provider = authentik_provider_oauth2.client[each.key].id
  meta_launch_url   = each.value.launch_url
}

resource "vault_mount" "authentik" {
  path        = "authentik"
  type        = "kv-v2"
  description = "OIDC client credentials, one path per consuming namespace."
}

resource "vault_kv_secret_v2" "oidc_client" {
  for_each = local.oidc_clients

  mount = vault_mount.authentik.path
  name  = "${each.value.namespace}/${each.key}"

  data_json = jsonencode({
    client_id     = authentik_provider_oauth2.client[each.key].client_id
    client_secret = random_password.oidc_client_secret[each.key].result
  })
}

resource "vault_policy" "oidc_client_read" {
  for_each = local.oidc_clients

  name = "authentik-${each.value.namespace}-${each.key}"

  policy = <<-EOT
    path "${vault_mount.authentik.path}/data/${each.value.namespace}/${each.key}" {
      capabilities = ["read"]
    }

    path "${vault_mount.authentik.path}/metadata/${each.value.namespace}/${each.key}" {
      capabilities = ["read"]
    }
  EOT
}

resource "vault_kubernetes_auth_backend_role" "oidc_namespace" {
  for_each = local.oidc_namespace_policies

  backend   = "kubernetes"
  role_name = "authentik-${each.key}"

  bound_service_account_names      = ["*"]
  bound_service_account_namespaces = [each.key]

  token_policies = each.value
  token_ttl      = 3600
}
