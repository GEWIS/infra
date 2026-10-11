# Machines that have manually been enrolled with setup keys

locals {
  pcgewis1  = "PCGEWIS1"
  pcgewis2  = "PCGEWIS2"
  pcgewis3  = "PCGEWIS3"
  pcgewis4  = "PCGEWIS4"
  pcgewis5  = "PCGEWIS5"
  pcgewis6  = "PCGEWIS6"
  pcgewis7  = "PCGEWIS7"
  pcgewis8  = "PCGEWIS8"
  pcgewis9  = "PCGEWIS9"
  pcgewis10 = "PCGEWIS10"
  room_pcs  = [local.pcgewis1, local.pcgewis2, local.pcgewis3, local.pcgewis4, local.pcgewis5, local.pcgewis6, local.pcgewis7, local.pcgewis8, local.pcgewis9, local.pcgewis10]

  pcgewisa    = "pcgewisa"
  pcgewisb    = "pcgewisb"
  pcgewisc    = "pcgewisc"
  pcgewisd    = "pcgewisd"
  pcgewishok  = "PCGEWISHOK"
  pcgewisinfo = "pcgewisinfo"
  service_pcs = [local.pcgewisa, local.pcgewisb, local.pcgewisc, local.pcgewisd, local.pcgewishok, local.pcgewisinfo]

  gewisdc02          = "GEWISDC02"
  gewisdc03          = "GEWISDC03"
  domain_controllers = [local.gewisdc02, local.gewisdc03]

  swarm201 = "swarm201"
  swarm202 = "swarm202"
  swarm203 = "swarm203"
  swarm    = [local.swarm201, local.swarm202, local.swarm203]

  gewisapp01     = "GEWISAPP01"
  gewisfiles01   = "GEWISFILES01"
  gewismgmt      = "GEWISMGMT"
  gewisbackup    = "GEWISBACKUP"
  gewiscontainer = "gewiscontainer"
  gewismail      = "gewismail"
  gewissecurity2 = "GEWISSECURITY2"
  gewisvdesktop  = "GEWISvDesktop"
  gewisweb       = "gewisweb"
  s3-01          = "s3-01"

  all_peers = concat(local.room_pcs, local.service_pcs, local.domain_controllers, local.swarm, [
    local.gewisapp01,
    local.gewisfiles01,
    local.gewismgmt,
    local.gewisbackup,
    local.gewiscontainer,
    local.gewismail,
    local.gewissecurity2,
    local.gewisvdesktop,
    local.gewisweb,
    local.s3-01
  ])

  peer_ids = { for name, peer in data.netbird_peer.peers : name => peer.id }
}

data "netbird_peer" "peers" {
  for_each = toset(local.all_peers)

  name = each.value
}
