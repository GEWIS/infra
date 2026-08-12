locals {
  proxy_clients = {
    hubble = {
      display_name  = "Hubble"
      external_host = "https://hubble.cbc.gewis.nl:8443"
    }
  }
}

data "authentik_service_connection_kubernetes" "local" {
  name = "Local Kubernetes Cluster"
}

resource "authentik_provider_proxy" "client" {
  for_each = local.proxy_clients

  name          = each.key
  mode          = "forward_single"
  external_host = each.value.external_host

  authorization_flow = data.authentik_flow.authorization.id
  invalidation_flow  = data.authentik_flow.invalidation.id
}

resource "authentik_application" "proxy" {
  for_each = local.proxy_clients

  name              = each.value.display_name
  slug              = each.key
  protocol_provider = authentik_provider_proxy.client[each.key].id
  meta_launch_url   = each.value.external_host
}

resource "authentik_outpost" "proxy" {
  name               = "cbc"
  type               = "proxy"
  service_connection = data.authentik_service_connection_kubernetes.local.id
  protocol_providers = [for provider in authentik_provider_proxy.client : provider.id]
}
