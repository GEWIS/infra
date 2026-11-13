resource "netbird_policy" "admin_to_router_admin" {
  name        = "CBC Admin to Router"
  description = "CBC Admin users need to be able to reach the router for management purposes."
  enabled     = true

  rule {
    name          = "CBC Admin to Router"
    action        = "accept"
    bidirectional = false
    enabled       = true
    protocol      = "tcp"
    ports         = [8291]
    sources       = [data.netbird_group.cbc_admins.id]
    destinations  = [netbird_group.router_mgmt.id]
  }
}