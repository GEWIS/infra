# Storage

One bucket per component, provisioned by `terraform/garage-buckets` — see
[`garage-buckets.md`](../garage-buckets/index.md).

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
