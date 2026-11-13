resource "netbird_account_settings" "example" {
  auto_update_version                 = "disabled"
  dns_domain                          = "net.nb.gewis.nl"
  groups_propagation_enabled          = true
  jwt_allow_groups                    = []
  jwt_groups_claim_name               = "groups"
  jwt_groups_enabled                  = true
  lazy_connection_enabled             = false
  network_range                       = "10.64.0.0/16"
  peer_approval_enabled               = false
  peer_expose_enabled                 = false
  peer_login_expiration               = 86400
  peer_login_expiration_enabled       = true
  regular_users_view_blocked          = true
  routing_peer_dns_resolution_enabled = true
  user_approval_required              = false
}