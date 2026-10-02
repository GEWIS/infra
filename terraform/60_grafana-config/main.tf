locals {
  tenants = toset([
    "CBC",
    "ABC-CRM",
    "ABC-DB",
    "ABC-EOU",
    "ABC-NC",
    "ABC-POS",
    "ABC-WEB",
  ])

  federated_tenants = join("|", sort(local.tenants))

  loki_url  = "http://loki.observability.svc.cluster.local:3100"
  mimir_url = "http://mimir.observability.svc.cluster.local:8080/prometheus"
  tempo_url = "http://tempo.observability.svc.cluster.local:3200"

  scope = { for tenant in local.tenants : tenant => tenant == "CBC" ? local.federated_tenants : tenant }
}

resource "grafana_organization" "tenant" {
  for_each = local.tenants

  name = each.value
}

resource "grafana_data_source" "loki" {
  for_each = local.tenants

  org_id = grafana_organization.tenant[each.value].org_id
  type   = "loki"
  name   = "Loki"
  uid    = "loki-${lower(each.value)}"
  url    = local.loki_url

  http_headers = {
    "X-Scope-OrgID" = local.scope[each.value]
  }
}

resource "grafana_data_source" "mimir" {
  for_each = local.tenants

  org_id     = grafana_organization.tenant[each.value].org_id
  type       = "prometheus"
  name       = "Mimir"
  uid        = "mimir-${lower(each.value)}"
  url        = local.mimir_url
  is_default = true

  http_headers = {
    "X-Scope-OrgID" = local.scope[each.value]
  }

  json_data_encoded = jsonencode({
    httpMethod     = "POST"
    prometheusType = "Mimir"
  })
}

resource "grafana_data_source" "tempo" {
  for_each = local.tenants

  org_id = grafana_organization.tenant[each.value].org_id
  type   = "tempo"
  name   = "Tempo"
  uid    = "tempo-${lower(each.value)}"
  url    = local.tempo_url

  http_headers = {
    "X-Scope-OrgID" = local.scope[each.value]
  }

  json_data_encoded = jsonencode({
    tracesToLogsV2 = {
      datasourceUid      = "loki-${lower(each.value)}"
      spanStartTimeShift = "-5m"
      spanEndTimeShift   = "5m"
      filterByTraceID    = true
    }
    tracesToMetrics = {
      datasourceUid = "mimir-${lower(each.value)}"
    }
  })
}

resource "grafana_data_source" "loki_live" {
  org_id = grafana_organization.tenant["CBC"].org_id
  type   = "loki"
  name   = "Loki (CBC only, live tail)"
  uid    = "loki-cbc-live"
  url    = local.loki_url

  http_headers = {
    "X-Scope-OrgID" = "CBC"
  }
}
