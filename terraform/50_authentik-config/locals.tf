locals {
  kubeconfig_path = coalesce(var.kubeconfig_path, "${path.module}/../../.kube/config")

  openbao_login_group = "CBC - Application Hosting Team (ADM)"

  gehack_hosts = ["loom", "imaged", "grafana"]
  gehack_group = "Organ - GEHACK"

  proxy_clients = merge(
    {
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
    },
    {
      for host in local.gehack_hosts : "gehack-${host}" => {
        display_name  = "GEHACK ${host}"
        external_host = "https://${host}.gehack.nl"
      }
    },
  )

  proxy_access_groups = merge(
    {
      longhorn = [
        "CBC - Application Hosting Team (ADM)",
        "CBC - Backup Team",
        "CBC - Filehosting and backup (ADM)",
      ]
    },
    { for host in local.gehack_hosts : "gehack-${host}" => [local.gehack_group] },
  )
}
