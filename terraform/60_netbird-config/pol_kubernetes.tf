resource "netbird_policy" "k8s_egress_to_proxy" {
  name        = "K8s Egress to Proxy Hosts"
  description = "The Netbird Network Router in the K8s cluster needs to be able to reach the other proxy hosts in order to proxy things to those proxy hosts."
  enabled     = true

  rule {
    name          = "K8s Egress to Proxy Hosts"
    action        = "accept"
    bidirectional = false
    enabled       = true
    protocol      = "tcp"
    sources       = [data.netbird_group.k8s_network_router.id]
    destinations  = [netbird_group.proxy_hosts.id]
  }
}