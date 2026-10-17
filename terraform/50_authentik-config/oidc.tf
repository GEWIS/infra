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
