# Tenancy is the design, not a feature

Seven tenants, one Kubernetes namespace group each, plus `CBC` which sees all of
them. That requirement drives every other decision here.

| Layer | What enforces the boundary |
| --- | --- |
| Ingest | Alloy derives the tenant from `__meta_kubernetes_namespace`. A workload cannot claim a tenant; it has no say in it. |
| Storage | Loki, Mimir and Tempo all run with multi-tenancy on. A read without `X-Scope-OrgID` is refused; a read with another tenant's ID returns that tenant's data, never yours. |
| Grafana | One organization per tenant. Its datasources carry the tenant in `http_headers`, which only an org **Admin** can change — so tenants map to `Viewer`/`Editor` and never `Admin`. |

`Editor` is safe to hand out. Grafana's permission table makes *Add, edit, delete
data sources* an org-**Admin** capability, so an Editor can build dashboards and
use Explore but cannot touch the `X-Scope-OrgID` header their queries carry. The
boundary does not depend on withholding `-RW`.

`Viewer` is the weaker seat in a way that matters here: viewers can query
datasources through a dashboard, but cannot access Explore. A `-RO` account
therefore sees only what is provisioned for its org, and dashboards are
provisioned for CBC alone — so for every other tenant, `-RW` is still the only
role that gives anything to look at.

`CBC` is not a special case in the backends. It is an ordinary tenant whose
datasources send every tenant ID pipe-separated, which all three engines accept
as a federated read:

| Backend | Setting |
| --- | --- |
| Loki | `querier.multi_tenant_queries_enabled: true` |
| Mimir | `tenant_federation.enabled: true` |
| Tempo | `query_frontend.multi_tenant_queries_enabled: true` |

The federated header is `join("|", sort(local.tenants))` in
`terraform/grafana-config`, never typed by hand. **Tenant IDs are
case-sensitive** and federation enumerates them exactly, so a `cbc` written
anywhere would be a second, invisible tenant. There is one spelling, `CBC`, and
it comes from that one list.

Loki tags federated results with `__tenant_id__`, so CBC can filter or group by
tenant inside a single query: `{app="foo", __tenant_id__=~"ABC-.+"}`.

## Adding a tenant touches two places

1. `terraform/grafana-config` — one entry in `local.tenants`, then `tofu apply`.
   That creates the org, its three datasources, and widens CBC's federated header.
2. `flux/apps/observability/alloy/` — one relabel rule in `logs.yaml` mapping the
   namespace to the tenant, and one `prometheus.relabel` + `prometheus.remote_write`
   pair in `metrics.yaml`.

Nothing per-tenant is provisioned in Garage. Tenancy is a prefix inside the
shared `loki`, `mimir` and `tempo` buckets, so the bucket layout never changes.

The namespaces the ABC tenants map to **do not exist yet**. That is harmless: a
relabel rule that never matches produces no data, and querying an empty tenant
returns an empty result rather than an error. The tenant names are the real ones
from `fleet-infra` so the directory groups (`GRAFANA-ABC_CRM-RO`, …) already
resolve, which makes the isolation testable before any workload lands.
