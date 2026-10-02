locals {
  kubeconfig_path = coalesce(var.kubeconfig_path, "${path.module}/../../.kube/config")

  openbao_login_group = "CBC - Application Hosting Team (ADM)"

  oidc_clients = {
    grafana = {
      display_name  = "Grafana"
      namespace     = "observability"
      launch_url    = "https://grafana.cbc.gewis.nl:8443/"
      redirect_uris = ["https://grafana.cbc.gewis.nl:8443/login/generic_oauth"]
    }
  }

  proxy_clients = {
    hubble = {
      display_name  = "Hubble"
      external_host = "https://hubble.cbc.gewis.nl:8443"
    }
    flux = {
      display_name  = "Flux"
      external_host = "https://flux.cbc.gewis.nl:8443"
    }
  }
}
