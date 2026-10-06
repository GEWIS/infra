# Collection

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

## API server histograms are dropped

The `apiserver` job keeps `_count` and `_sum` but drops every `_bucket` series of
`apiserver_*` and `etcd_*` metrics (`prometheus.relabel "apiserver"`). Three API
servers expose high-resolution histograms per resource and verb, about 110,000
series on their own, which together with everything else exceeds Mimir's default per-tenant limit of
150,000 active series and makes Mimir refuse every new series for `CBC`. Rates and
averages (`_sum / _count`) still work; percentiles for the API server and etcd do
not. To keep one histogram, exclude it from the regex.
