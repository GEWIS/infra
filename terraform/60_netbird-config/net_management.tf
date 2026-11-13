resource "netbird_network" "management" {
  name        = "Management"
  description = "Devices on the management VLAN that do not run Netbird themselves."
}

resource "netbird_network_router" "management_gewismgmt" {
  network_id = netbird_network.management.id
  peer       = local.peer_ids[local.gewismgmt]
  enabled    = true
  masquerade = true
}

resource "netbird_group" "router_mgmt" {
  name = "Router (MGMT)"
}

resource "netbird_network_resource" "router_mgmt" {
  name       = "Router (MGMT)"
  network_id = netbird_network.management.id
  address    = "10.82.30.1/32"
  groups     = [netbird_group.router_mgmt.id]
}
