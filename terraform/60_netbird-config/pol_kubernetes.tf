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
resource "netbird_policy" "admin_to_k8s_api" {
  name        = "CBC Admin to K8s API"
  description = "CBC Admin users need to be able to reach the Kubernetes API."
  enabled     = true

  rule {
    name          = "CBC Admin to K8s API"
    action        = "accept"
    bidirectional = false
    enabled       = true
    protocol      = "tcp"
    ports         = [443]
    sources       = [data.netbird_group.cbc_admins.id]
    destinations  = [data.netbird_group.k8s_api.id]
  }
}
