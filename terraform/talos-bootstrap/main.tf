locals {
  cilium_values = {
    ipam                 = { mode = "kubernetes" }
    kubeProxyReplacement = true
    k8sServiceHost       = "localhost"
    k8sServicePort       = 7445

    ipv4 = { enabled = true }
    ipv6 = { enabled = true }

    encryption = {
      enabled = true
      type    = "wireguard"
    }

    cgroup = {
      autoMount = { enabled = false }
      hostRoot  = "/sys/fs/cgroup"
    }

    gatewayAPI = {
      enabled     = true
      hostNetwork = { enabled = true }
    }

    envoy = {
      enabled = true
      securityContext = {
        capabilities = {
          keepCapNetBindService = true
          envoy = [
            "NET_ADMIN",
            "SYS_ADMIN",
            "NET_BIND_SERVICE",
          ]
        }
      }
    }

    prometheus = { enabled = true }

    hubble = {
      relay = { enabled = true }
      ui    = { enabled = true }
    }

    securityContext = {
      capabilities = {
        ciliumAgent = [
          "CHOWN",
          "KILL",
          "NET_ADMIN",
          "NET_RAW",
          "IPC_LOCK",
          "SYS_ADMIN",
          "SYS_RESOURCE",
          "DAC_OVERRIDE",
          "FOWNER",
          "SETGID",
          "SETUID",
        ]
        cleanCiliumState = [
          "NET_ADMIN",
          "SYS_ADMIN",
          "SYS_RESOURCE",
        ]
      }
    }
  }
}

resource "helm_release" "cilium" {
  name       = "cilium"
  repository = "https://helm.cilium.io/"
  chart      = "cilium"
  version    = "1.20.0"
  namespace  = "kube-system"

  values = [yamlencode(local.cilium_values)]

  depends_on = [kubectl_manifest.gateway_api_crds]
}
