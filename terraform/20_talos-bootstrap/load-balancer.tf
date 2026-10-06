resource "kubectl_manifest" "lb_ip_pool" {
  yaml_body = yamlencode({
    apiVersion = "cilium.io/v2"
    kind       = "CiliumLoadBalancerIPPool"
    metadata   = { name = "default" }
    spec = {
      blocks = [{ start = "10.82.50.200", stop = "10.82.50.229" }]
    }
  })

  depends_on = [helm_release.cilium]
}

resource "kubectl_manifest" "l2_announcement_policy" {
  yaml_body = yamlencode({
    apiVersion = "cilium.io/v2alpha1"
    kind       = "CiliumL2AnnouncementPolicy"
    metadata   = { name = "default" }
    spec = {
      loadBalancerIPs = true
    }
  })

  depends_on = [helm_release.cilium]
}
