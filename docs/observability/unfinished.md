# Two things that are deliberately not finished

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
