resource "netbird_group" "gewismgmt" {
  name  = "GEWISMGMT"
  peers = [local.peer_ids[local.gewismgmt]]
}

resource "netbird_policy" "admin_to_gewismgmt" {
  for_each = toset(["tcp", "udp"])

  name        = "CBC Admin to GEWISMGMT (${upper(each.key)})"
  description = "CBC Admin users manage the domain from GEWISMGMT over RDP."
  enabled     = true

  rule {
    name          = "CBC Admin to GEWISMGMT (${upper(each.key)})"
    action        = "accept"
    bidirectional = false
    enabled       = true
    protocol      = each.key
    ports         = [3389]
    sources       = [data.netbird_group.cbc_admins.id]
    destinations  = [netbird_group.gewismgmt.id]
  }
}
