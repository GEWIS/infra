locals {
  kubeconfig_path = coalesce(var.kubeconfig_path, "${path.module}/../../.kube/config")

  openbao_login_group = "CBC - Application Hosting Team (ADM)"

  proxy_clients = {
    hubble = {
      display_name  = "Hubble"
      external_host = "https://hubble.gewis.nl"
    }
    flux = {
      display_name  = "Flux"
      external_host = "https://flux.gewis.nl"
    }
    longhorn = {
      display_name  = "Longhorn"
      external_host = "https://longhorn.gewis.nl"
    }
  }

  proxy_access_groups = {
    longhorn = [
      "CBC - Application Hosting Team (ADM)",
      "CBC - Backup Team",
      "CBC - Filehosting and backup (ADM)",
    ]
  }
}
