
resource "netbird_group" "room_pcs" {
  name  = "GEWIS Room PCs"
  peers = [for name in local.room_pcs : local.peer_ids[name]]
}

resource "netbird_group" "managed" {
  name  = "All PCs"
  peers = [for name in local.all_peers : local.peer_ids[name]]
}
