# observability

Logs, metrics, traces and dashboards, all backed by Garage rather than Longhorn.
Loki, Mimir, Tempo, Grafana, kube-state-metrics and two Alloy collectors live in
`observability`; the node exporter lives on its own, for a reason given below.

Everything is reconciled by the `services` layer — this is infrastructure tenants
consume, not a tenant application. That layer depends on `config` **and**
`openbao`, because the three S3 credentials arrive through External Secrets.
