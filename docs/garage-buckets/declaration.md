# The declaration

Everything is driven by one map in `main.tf`:

```hcl
buckets = {
  loki  = { size_gib = 20, namespace = "observability" }
  mimir = { size_gib = 20, namespace = "observability" }
  tempo = { size_gib = 10, namespace = "observability" }
}
```

The key is the Garage bucket name. `size_gib` becomes a Garage quota, `namespace`
is the only namespace whose pods may read the resulting credentials.

Per entry, one apply produces:

| Object | Where |
| --- | --- |
| Bucket with `max_size` quota | Garage |
| Access key `<namespace>-<bucket>`, non-expiring | Garage |
| Read+write grant on that bucket for that key, **not owner** | Garage |
| KV entry `garage/<namespace>/<bucket>` — `bucket`, `endpoint`, `region`, `access_key_id`, `secret_access_key` | OpenBao |
| Policy `garage-<namespace>-<bucket>`, `read` on that one path | OpenBao |

Plus one Kubernetes auth role per *namespace*, `garage-<namespace>`, bound to
`bound_service_account_namespaces = [<namespace>]` and carrying every policy for
that namespace's buckets. Service accounts are bound as `*`: any pod in the
namespace, nothing outside it.

`size_gib` is a cap, not a reservation. The node advertises 90G with
`replication_factor = 1`, so the quotas may sum to more than the disk — Garage
will hit ENOSPC before the quota if you overcommit.
