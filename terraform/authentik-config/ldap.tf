data "authentik_property_mapping_source_ldap" "user" {
  managed_list = [
    "goauthentik.io/sources/ldap/default-name",
    "goauthentik.io/sources/ldap/default-mail",
    "goauthentik.io/sources/ldap/ms-samaccountname",
    "goauthentik.io/sources/ldap/ms-userprincipalname",
    "goauthentik.io/sources/ldap/ms-givenName",
    "goauthentik.io/sources/ldap/ms-sn",
  ]
}

resource "authentik_property_mapping_source_ldap" "user_dn" {
  name       = "GEWISWG: distinguishedName"
  expression = "return {\"attributes\": {\"distinguishedName\": dn}}"
}

data "authentik_property_mapping_source_ldap" "group" {
  managed_list = [
    "goauthentik.io/sources/ldap/default-name",
  ]
}

resource "authentik_source_ldap" "gewiswg" {
  name       = "GEWISWG"
  slug       = "gewiswg"
  server_uri = "ldaps://ldaps.gewis.nl"
  start_tls  = false

  bind_cn       = "svc-authentik@gewiswg.gewis.nl"
  bind_password = var.ad_bind_password

  base_dn                 = "DC=GEWISWG,DC=GEWIS,DC=nl"
  user_object_filter      = "(&(objectClass=user)(memberOf:1.2.840.113556.1.4.1941:=CN=PRIV - Logon Keycloak GEWISWG,OU=Privileges,OU=Groups,DC=gewiswg,DC=gewis,DC=nl))"
  group_object_filter     = "(objectClass=group)"
  group_membership_field  = "memberOf:1.2.840.113556.1.4.1941:"
  object_uniqueness_field = "objectSid"

  sync_users              = true
  sync_users_password     = false
  sync_groups             = true
  lookup_groups_from_user = true

  property_mappings = concat(
    data.authentik_property_mapping_source_ldap.user.ids,
    [authentik_property_mapping_source_ldap.user_dn.id],
  )
  property_mappings_group = data.authentik_property_mapping_source_ldap.group.ids
}
