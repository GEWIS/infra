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

  config = jsonencode({
    authentik_host                   = "${var.authentik_url}/"
    authentik_host_browser           = ""
    authentik_host_insecure          = false
    container_image                  = null
    docker_labels                    = null
    docker_map_ports                 = true
    docker_network                   = null
    kubernetes_disable_x509_strict   = false
    kubernetes_disabled_components   = ["ingress", "httproute", "traefik middleware"]
    kubernetes_httproute_annotations = {}
    kubernetes_httproute_parent_refs = []
    kubernetes_image_pull_secrets    = []
    kubernetes_ingress_annotations   = {}
    kubernetes_ingress_class_name    = null
    kubernetes_ingress_path_type     = null
    kubernetes_ingress_secret_name   = "authentik-outpost-tls"
    kubernetes_json_patches          = null
    kubernetes_namespace             = "authentik"
    kubernetes_replicas              = 1
    kubernetes_service_type          = "ClusterIP"
    log_level                        = "info"
    object_naming_template           = "ak-outpost-%(name)s"
    refresh_interval                 = "minutes=5"
  })
}
