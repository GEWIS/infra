# observability

Logs, metrics, traces and dashboards, all backed by Garage rather than Longhorn.
Loki, Mimir, Tempo, Grafana, kube-state-metrics and two Alloy collectors live in
`observability`; the node exporter lives on its own, for a reason given below.

Everything is reconciled by the `services` layer — this is infrastructure tenants
consume, not a tenant application. That layer depends on `config` **and**
`openbao`, because the three S3 credentials arrive through External Secrets.

## Tenancy is the design, not a feature

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
datasources through a dashboard, but cannot access Explore. With no dashboards
provisioned yet, a `-RO` account therefore sees an empty Grafana. Until dashboards
exist, `-RW` is the only role that gives a tenant anything to look at.

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

### Adding a tenant touches two places

1. `terraform/grafana-config` — one entry in `local.tenants`, then `tofu apply`.
   That creates the org, its three datasources, and widens CBC's federated header.
2. `flux/services/observability/alloy/` — one relabel rule in `logs.yaml` mapping the
   namespace to the tenant, and one `prometheus.relabel` + `prometheus.remote_write`
   pair in `metrics.yaml`.

Nothing per-tenant is provisioned in Garage. Tenancy is a prefix inside the
shared `loki`, `mimir` and `tempo` buckets, so the bucket layout never changes.

The namespaces the ABC tenants map to **do not exist yet**. That is harmless: a
relabel rule that never matches produces no data, and querying an empty tenant
returns an empty result rather than an error. The tenant names are the real ones
from `fleet-infra` so the Keycloak roles (`GRAFANA-ABC_CRM-RO`, …) already
resolve, which makes the isolation testable before any workload lands.

## Grafana organizations cannot be provisioned from the cluster

Grafana OSS has no declarative org mechanism, and this is not an oversight to
route around:

- The Helm chart provisions datasources and dashboards, never orgs.
- `grafana-operator` v5 has CRDs for dashboards, datasources, folders, service
  accounts and alerting — none for orgs.
- Grafana's own `grizzly` has handlers for everything except orgs.
- The new app-platform IAM API (`iam.grafana.app/v0alpha1`) serves users, teams
  and service accounts. Orgs are absent; Cloud replaced them with stacks.

And an org that does not exist fails **silently**: `org_role_mapper.go` resolves
a non-numeric org through `GetByName` and, on a miss, logs `"Could not fetch
OrgID. Skipping."` — with `role_attribute_strict: true` it discards *the entire
mapping for every user*, not just the bad entry. `org_sync.go` likewise does
`if errors.Is(err, org.ErrOrgNotFound) { continue }`.

So orgs and their datasources are owned by `terraform/grafana-config`, in the
same style as `garage-buckets` and `openbao-config`. Both chart sidecars are
disabled, so everything org-scoped has exactly one owner.

**Nothing provisions dashboards yet**, and the dashboard sidecar is not the way
to add them later. Its provider hardcodes `orgid: 1`, and one provider means one
organization — so a single sidecar can never serve seven tenants, and org 1 is
the empty `Main Org.` that no role maps into. Enabling it would provision every
`grafana_dashboard`-labelled ConfigMap into an organization nobody can see,
silently. Pointing it at CBC instead would hardcode a tofu-assigned,
auto-incremented org ID into a HelmRelease. When dashboards are wanted, they
belong beside the datasources in the tofu root, keyed by tenant.

## Who is the server administrator

There is no OIDC path to `GrafanaAdmin`. `role_attribute_path` and
`allow_assign_grafana_admin` are deliberately absent, so GEWISWG accounts receive
organization roles and nothing more. Server administration belongs to the local
`admin` account from the SealedSecret.

The login form is therefore **hidden** (`disable_login_form: true`), and the UI is
GEWISWG-only. That is a deliberate choice, not an oversight: server-level
administration happens through `terraform/grafana-config`, not by clicking. The
local `admin` remains fully usable because `[auth.basic]` is untouched — basic
auth against the API keeps working, which is exactly how that tofu root
authenticates.

What this costs: nothing reachable in the browser can administer the server. No
organization list, no user administration, no server settings. If a task has no
tofu resource, it is a `curl` against the API, or a temporary revert of this one
line.

If OIDC itself breaks — Keycloak unreachable, client secret rotated out from under
the release — there is no interactive way in at all. Recovery is to set
`disable_login_form: false` in git and let Flux reconcile, which takes about as
long as a reconcile. Keep that in mind before rotating the Keycloak client.

`role_attribute_strict` is `true`. An account whose roles match no mapping entry
is refused outright rather than landing in the empty `Main Org.` as a Viewer, so
`Main Org.` stays empty and access is exactly what GEWISWG says it is.

That setting couples logins to the tofu root more tightly than it looks.
`ParseOrgMappingSettings` resolves every org name at evaluation time, and under
strict mode a **single** unresolvable name discards the whole mapping — not just
that entry — which denies every user, not only the one whose role is affected. So
the seven organizations must exist before this is enabled, and destroying or
renaming one breaks all logins at once. `tofu apply` is what keeps them alive.

If a change here does lock people out, the way back is to revert it in git and let
Flux reconcile. Resetting the admin password does not help when the form is
hidden, and an apply can still repair orgs and mappings over the API while the UI
is unusable.

## Mimir is hand-written, and that is the smaller option

`mimir-distributed` is microservices-only — upstream says so outright — and as of
chart 6.1.0 it defaults to the Kafka ingest-storage architecture: `kafka.enabled:
true`, with `ingest_storage: enabled: true` written unconditionally into the
config and `ingester.push_grpc_method_enabled: false`. Disabling Kafka only drops
the broker address; the ingester still refuses gRPC pushes. Running it here would
mean a Kafka StatefulSet plus ten services plus four memcached tiers on three
nodes.

Monolithic mode is one flag, `-target=all`, which runs QueryFrontend,
QueryScheduler, Querier, Ingester, Distributor, StoreGateway, **Ruler** and
**Compactor** (`pkg/mimir/modules.go`). Two consequences:

- Ruler is included, so `ruler_storage` must be configured or the process fails.
- Alertmanager is not, so alertmanager storage is skipped entirely.

Both live in the one `mimir` bucket, separated by `storage_prefix`. That field
"may only contain digits and English alphabet letters", so the prefixes are
`blocks` and `ruler` — a path like `mimir/blocks` is rejected.

Monolithic does not forfeit HA. Upstream supports scaling it horizontally, so the
rings use **memberlist from day one** rather than `inmemory`; going to three
replicas is `replicas: 3` plus `replication_factor: 3`, not a re-architecture.
The same holds for Loki's SingleBinary mode. Tempo's single-binary chart has no
ring, so scaling *it* means moving to `tempo-distributed` — cheap, since the
blocks are already in S3.

### Mimir is configured entirely by flags, deliberately

There is no ConfigMap. Every setting is a container argument, which means the
configuration *is* the pod spec: Flux applies a change, the StatefulSet's
template changes, and the pod rolls. A config file in a ConfigMap would be
applied silently and never restart anything — Mimir has no hot reload for its
main config — and the usual fix, a hashed `configMapGenerator`, needs a
`kustomization.yaml` that this tree deliberately does not have, since every layer
here relies on Flux's recursive scan.

The cost is that the two S3 keys reach the process through `$(VAR)` argument
expansion, so kubelet writes them into the container's argv. The manifest itself
holds only the placeholder, and the values come from the ESO-managed Secret via
`secretKeyRef` — but anyone who can `exec` into the pod can read them from
`/proc`, which is also true of the environment-variable form.

Per-tenant limits, when they arrive, belong in a runtime configuration file
rather than here: that one Mimir *does* reload without a restart.

## Storage

One bucket per component, provisioned by `terraform/garage-buckets` — see
[`garage-buckets.md`](garage-buckets.md).

| Component | Bucket | Prefixes | Local disk |
| --- | --- | --- | --- |
| Loki | `loki` | chunks and ruler share it | 10Gi Longhorn, WAL and index staging |
| Mimir | `mimir` | `blocks`, `ruler` | 20Gi Longhorn, TSDB head, compactor scratch, store-gateway sync |
| Tempo | `tempo` | — | 5Gi Longhorn, WAL |

Garage needs the same three things everywhere: path-style addressing
(`s3ForcePathStyle` / `bucket_lookup_type: path` / `forcepathstyle`), `insecure`
for plain HTTP on port 3900, and region `garage`.

Retention is **in-app**, 30 days everywhere — `limits_config.retention_period`,
`compactor_blocks_retention_period` and `tempo.retention`. Not S3 lifecycle
rules: the `vhco-pro/garage` provider exposes buckets, keys and permissions only,
so a lifecycle policy is not something this repo can declare.

Only the two key fields come from OpenBao. Endpoint, region and bucket are not
secrets and sit in the values. Each component reads the keys as environment
variables and expands them with `-config.expand-env=true`, so no credential is
ever templated into a ConfigMap.

Loki's chart still renders an inert `boltdb_shipper` index-gateway stanza. No
schema period references it — the single schema entry is `tsdb`/`v13` — so it is
dead config, not a second index.

## Collection

Two Alloy releases, split to avoid counting everything three times:

| Release | Shape | Collects |
| --- | --- | --- |
| `alloy-logs` | DaemonSet | Pod logs, **node-local only** via a `spec.nodeName` field selector |
| `alloy-metrics` | Deployment, 1 replica | kubelet, cadvisor, node exporter, kube-state-metrics, annotated pods, and the OTLP receiver |

The field selector is load-bearing. `loki.source.kubernetes` tails through the
API server, not the node filesystem, so without it every DaemonSet pod would tail
every pod in the cluster and ship three copies of every line.

Metrics run from a single Deployment for the mirror-image reason: kubelet and
cadvisor are scraped directly on `:10250` across all nodes, and kube-state-metrics
is a singleton. Three collectors doing that would triple every series.

Log tenancy uses `loki.process` with `stage.tenant` reading a `tenant` label
computed during relabelling; the label is dropped afterwards, since the tenant
already partitions the data. Metric tenancy cannot work that way — Mimir takes
the tenant only from the request header — so there is one `prometheus.relabel`
plus one `prometheus.remote_write` per tenant. Alloy's `foreach` block would
collapse that repetition, but it is marked experimental and tenant isolation is
not the place for that.

`CBC` is the fallback: log lines from unmapped namespaces get `CBC`, and the CBC
metrics path drops anything whose `namespace` label belongs to a tenant.

## Two things that are deliberately not finished

**Per-tenant trace routing.** Alloy accepts OTLP and forwards to Tempo as `CBC`.
Nothing emits traces yet, and Alloy has no routing processor or connector, so
per-tenant traces would mean `otelcol.processor.k8sattributes` plus a
filter-and-export pipeline per tenant — roughly a hundred lines that has never
seen a span. It is the same shape as the metrics fan-out and should be written
when there is a producer to test it against. Until then a tenant's Tempo
datasource is correctly empty rather than wrong.

**Live tailing on CBC's Loki datasource.** Loki's multi-tenant support covers
query endpoints only: `GET /loki/api/v1/tail` returns HTTP 400 when the header
names more than one tenant. CBC therefore has a second datasource, `Loki (CBC
only, live tail)`, pinned to the single tenant. Instant and range queries on the
federated one are unaffected.

## Pod Security, and why one namespace is privileged

Talos enforces the baseline standard, which forbids hostPath volumes. Exactly one
workload here needs them — the node exporter, reading `/proc` and `/sys` — so it
gets its own namespace, `node-exporter`, labelled
`pod-security.kubernetes.io/enforce: privileged`, in the same spirit as `dns` and
`traefik`.

`observability` itself carries **no PSA label** and stays baseline. Labelling the
whole stack privileged to satisfy one DaemonSet would drop enforcement for Loki,
Mimir, Tempo and Grafana as well. Alloy needs no host access at all: pod logs come
from the API server, kubelet and cadvisor over HTTPS, everything else over the pod
network.

## The one secret, and where it lives

`grafana-auth` carries `admin-user`, `admin-password`, `keycloak-client-id` and
`keycloak-client-secret`. It is a SealedSecret next to the chart that consumes
it, and it is the **only** copy: Grafana mounts it, and
`terraform/grafana-config` reads it back out of the cluster at apply time.

Sealing is offline — the pinned key pair lives in `secrets/sealed-secrets.yaml`,
so no cluster access is needed to produce the ciphertext:

```sh
sops -d --extract '["tls_crt"]' secrets/sealed-secrets.yaml > /tmp/sealing.crt
kubeseal --cert /tmp/sealing.crt --format yaml < /tmp/grafana-auth.yaml \
  > flux/services/observability/grafana/auth-sealed-secret.yaml
```

Write the plaintext input under `/tmp`, never in the working tree — nothing in
`.gitignore` would catch it, and a rule broad enough to catch it would also
shadow the sealed output.

Rotating the admin password is one resealed file. The tofu root picks the new
value up on its next apply because it never stored the old one.

## Applying

Flux brings up the workloads. The Grafana side is one apply once Grafana answers:

```sh
cd terraform/grafana-config
tofu init
tofu apply
```

The root has no credential of its own. It reads the `grafana-auth` Secret out of
the `observability` namespace with the `kubernetes` provider and authenticates as
that admin user, so the password exists in exactly one place — the SealedSecret
in git. This couples the root to the cluster, which costs nothing it was not
already paying: Grafana has to be up and reachable for an apply to do anything at
all. The kubeconfig defaults to the repository's `.kube/config`, which `.envrc`
mints.

## Verifying

Run these in order; each one gates the next.

```sh
bao kv get garage/observability/loki
kubectl -n observability get externalsecret
```

Then that data actually lands in Garage, which is the part worth proving — Loki
on Garage is well travelled, Mimir's and Tempo's object clients less so:

```sh
aws --endpoint-url http://10.82.50.100:3900 s3 ls s3://loki
aws --endpoint-url http://10.82.50.100:3900 s3 ls s3://mimir/blocks/
```

Then tenancy, where the negative results are the interesting ones:

```sh
curl -s "http://loki.observability.svc:3100/loki/api/v1/labels"
curl -s -H 'X-Scope-OrgID: CBC' "http://loki.observability.svc:3100/loki/api/v1/labels"
curl -s -H 'X-Scope-OrgID: ABC-CRM' "http://loki.observability.svc:3100/loki/api/v1/labels"
```

The first must be refused for want of a tenant, the second must return labels,
and the third must be empty — never CBC's.

Finally through Grafana: log in with GEWISWG, land in the `CBC` org as `Editor`,
and confirm the federated datasources return logs and `up{}`. An account holding
only `GRAFANA-ABC_CRM-RO` must land in exactly one org, see only that namespace,
and have no route to the rest.
