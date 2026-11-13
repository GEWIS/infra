resource "netbird_group" "room_pcs" {
  name  = "GEWIS Room PCs"
  peers = [for name in local.room_pcs : local.peer_ids[name]]
}

resource "netbird_group" "proxy_hosts" {
  name  = "Proxy Hosts"
  peers = [for name in [local.gewisweb, local.gewismail, local.gewiscontainer] : local.peer_ids[name]]
}