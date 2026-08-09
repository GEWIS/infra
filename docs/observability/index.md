# observability

Logs, metrics, traces and dashboards, all backed by Garage rather than Longhorn.
Loki, Mimir, Tempo, Grafana, kube-state-metrics and two Alloy collectors live in
`observability`; the node exporter lives on its own, for a reason given below.

Everything is reconciled by the `apps` layer. The stack consumes a database and
S3 credentials rather than providing them, so it sits above `services` — where a
workload that crashloops until its dependencies exist blocks nothing behind it.
