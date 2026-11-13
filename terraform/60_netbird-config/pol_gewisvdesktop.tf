resource "netbird_group" "gewisvdesktop" {
  name  = "GEWISvDesktop"
  peers = [local.peer_ids[local.gewisvdesktop]]
}

resource "netbird_policy" "members_to_gewisvdesktop" {
  for_each = toset(["tcp", "udp"])

  name        = "Members and Room PCs to GEWISvDesktop (${upper(each.key)})"
  description = "GEWIS members and the GEWIS Room PCs reach GEWISvDesktop over RDP."
  enabled     = true

  rule {
    name          = "Members and Room PCs to GEWISvDesktop (${upper(each.key)})"
    action        = "accept"
    bidirectional = false
    enabled       = true
    protocol      = each.key
    ports         = [3389]
    sources       = [data.netbird_group.gewis_members.id, netbird_group.room_pcs.id]
    destinations  = [netbird_group.gewisvdesktop.id]
  }
}
