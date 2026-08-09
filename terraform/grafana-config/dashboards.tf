locals {
  cbc_org_id   = grafana_organization.tenant["CBC"].org_id
  cbc_mimir_ds = grafana_data_source.mimir["CBC"].uid

  dashboards = {
    traefik            = { id = 17347, revision = 9 }
    coredns            = { id = 15762, revision = 22 }
    kubernetes_global  = { id = 15757, revision = 43 }
    kubernetes_nodes   = { id = 15759, revision = 40 }
    kubernetes_ns      = { id = 15758, revision = 46 }
    kubernetes_pods    = { id = 15760, revision = 39 }
    kubernetes_api     = { id = 15761, revision = 21 }
    node_exporter_full = { id = 1860, revision = 45 }
  }

  dashboards_pinned_datasource = {
    longhorn     = { id = 17626, revision = 1, placeholder = "DS_PROMETHEUS-LONGHORN" }
    cert_manager = { id = 22184, revision = 3, placeholder = "DS_PROMETHEUS" }
    openbao      = { id = 23725, revision = 1, placeholder = "DS_PROMXY" }
  }

  sealed_secrets_dashboard_url = "https://raw.githubusercontent.com/bitnami-labs/sealed-secrets/5d360fd400f0d93ac42d123eb81336a2d64d1772/contrib/prometheus-mixin/dashboards/sealed-secrets-controller.json"
}

data "http" "dashboard" {
  for_each = local.dashboards

  url = "https://grafana.com/api/dashboards/${each.value.id}/revisions/${each.value.revision}/download"
}

data "http" "dashboard_pinned_datasource" {
  for_each = local.dashboards_pinned_datasource

  url = "https://grafana.com/api/dashboards/${each.value.id}/revisions/${each.value.revision}/download"
}

data "http" "dashboard_sealed_secrets" {
  url = local.sealed_secrets_dashboard_url
}

resource "grafana_dashboard" "cbc" {
  for_each = local.dashboards

  org_id      = local.cbc_org_id
  overwrite   = true
  config_json = data.http.dashboard[each.key].response_body
}

resource "grafana_dashboard" "cbc_pinned_datasource" {
  for_each = local.dashboards_pinned_datasource

  org_id    = local.cbc_org_id
  overwrite = true
  config_json = replace(
    data.http.dashboard_pinned_datasource[each.key].response_body,
    "$${${each.value.placeholder}}",
    local.cbc_mimir_ds,
  )
}

resource "grafana_dashboard" "cbc_sealed_secrets" {
  org_id      = local.cbc_org_id
  overwrite   = true
  config_json = data.http.dashboard_sealed_secrets.response_body
}
