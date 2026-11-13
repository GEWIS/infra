locals {
  active_directory_ports = {
    tcp = [[53, 53], [88, 88], [135, 135], [389, 389], [445, 445], [464, 464], [636, 636], [3268, 3269], [9389, 9389], [49152, 65535]]
    udp = [[53, 53], [88, 88], [123, 123], [389, 389], [464, 464]]
  }
}

resource "netbird_group" "domain_controllers" {
  name  = "Domain Controllers"
  peers = [for name in local.domain_controllers : local.peer_ids[name]]
}

resource "netbird_policy" "all_to_domain_controllers" {
  for_each = local.active_directory_ports

  name        = "All to Domain Controllers (${upper(each.key)})"
  description = "Domain members reach Active Directory on the domain controllers' NetBird addresses."
  enabled     = true

  rule {
    name          = "All to Domain Controllers (${upper(each.key)})"
    action        = "accept"
    bidirectional = false
    enabled       = true
    protocol      = each.key
    port_ranges   = [for r in each.value : { start = r[0], end = r[1] }]
    sources       = [data.netbird_group.all.id]
    destinations  = [netbird_group.domain_controllers.id]
  }
}
