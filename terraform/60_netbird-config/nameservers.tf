resource "netbird_nameserver_group" "tue" {
  name        = "TU/e DNS"
  description = "The DNS servers of the TU/e"
  groups      = [data.netbird_group.all.id]
  primary     = true
  nameservers = [{
    ip   = "131.155.2.3"
    port = 53
    }, {
    ip   = "131.155.3.3"
    port = 53
  }]
}

resource "netbird_nameserver_group" "gewis" {
  name        = "GEWIS DNS"
  description = "The selfhosted CoreDNS server in the K8s cluster."
  groups      = [netbird_group.proxy_hosts.id]
  domains     = ["net.gewis.nl"]
  nameservers = [{
    ip   = "10.82.50.11"
    port = 53
    }, {
    ip   = "10.82.50.15"
    port = 53
  }]
}

resource "netbird_group" "gewis_dns" {
  name = "DNS Servers"
}

resource "netbird_network_resource" "gewis_dns_alpha" {
  name       = "GEWIS DNS Alpha"
  network_id = data.netbird_network.k8s_cluster.id
  address    = "10.82.50.11/32"
  groups     = [netbird_group.gewis_dns.id]
}

resource "netbird_network_resource" "gewis_dns_beta" {
  name       = "GEWIS DNS Beta"
  network_id = data.netbird_network.k8s_cluster.id
  address    = "10.82.50.15/32"
  groups     = [netbird_group.gewis_dns.id]
}

resource "netbird_policy" "all_to_dns_udp" {
  name        = "All to DNS"
  description = "Everybody should be able to access the DNS servers"
  enabled     = true

  rule {
    name          = "All to DNS"
    action        = "accept"
    bidirectional = false
    enabled       = true
    protocol      = "udp"
    ports         = [53]
    sources       = [data.netbird_group.all.id]
    destinations  = [netbird_group.gewis_dns.id]
  }
}
resource "netbird_policy" "all_to_dns_tcp" {
  name        = "All to DNS"
  description = "Everybody should be able to access the DNS servers"
  enabled     = true

  rule {
    name          = "All to DNS"
    action        = "accept"
    bidirectional = false
    enabled       = true
    protocol      = "tcp"
    ports         = [53]
    sources       = [data.netbird_group.all.id]
    destinations  = [netbird_group.gewis_dns.id]
  }
}