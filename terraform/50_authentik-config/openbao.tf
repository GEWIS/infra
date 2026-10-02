resource "random_password" "openbao_client_secret" {
  length  = 64
  special = false
}

resource "authentik_provider_oauth2" "openbao" {
  name          = "openbao"
  client_id     = "openbao"
  client_secret = random_password.openbao_client_secret.result
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
    {
      matching_mode     = "strict"
      redirect_uri_type = "authorization"
      url               = "${var.bao_address}/ui/vault/auth/oidc/oidc/callback"
    },
    {
      matching_mode     = "strict"
      redirect_uri_type = "authorization"
      url               = "http://localhost:8250/oidc/callback"
    },
  ]
}

resource "authentik_application" "openbao" {
  name              = "OpenBao"
  slug              = "openbao"
  protocol_provider = authentik_provider_oauth2.openbao.id
  meta_launch_url   = "${var.bao_address}/ui/vault/auth?with=oidc%2F"
}

resource "authentik_policy_expression" "openbao_login" {
  name       = "openbao: ${local.openbao_login_group}"
  expression = "return ${jsonencode(local.openbao_login_group)} in request.user.attributes.get(\"groups\", [])"
}

resource "authentik_policy_binding" "openbao_login" {
  target = authentik_application.openbao.uuid
  policy = authentik_policy_expression.openbao_login.id
  order  = 0
}

resource "vault_jwt_auth_backend_role" "authentik" {
  backend   = "oidc"
  role_name = "authentik"
  role_type = "oidc"

  user_claim            = "preferred_username"
  oidc_scopes           = ["openid", "profile", "email"]
  allowed_redirect_uris = [for uri in authentik_provider_oauth2.openbao.allowed_redirect_uris : uri.url]

  bound_claims = {
    groups = local.openbao_login_group
  }

  token_policies = ["ssh-sign-admin"]
  token_ttl      = 3600
}

resource "vault_generic_endpoint" "oidc_config" {
  path                 = "auth/oidc/config"
  ignore_absent_fields = true
  disable_delete       = true

  data_json = jsonencode({
    oidc_discovery_url = "${var.authentik_url}/application/o/${authentik_application.openbao.slug}/"
    bound_issuer       = "${var.authentik_url}/application/o/${authentik_application.openbao.slug}/"
    oidc_client_id     = authentik_provider_oauth2.openbao.client_id
    oidc_client_secret = random_password.openbao_client_secret.result
    default_role       = vault_jwt_auth_backend_role.authentik.role_name
  })
}
