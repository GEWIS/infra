# The declaration

Everything is driven by one map in `main.tf`:

```hcl
buckets = {
  loki     = { namespace = "observability" }
  mimir    = { namespace = "observability" }
  tempo    = { namespace = "observability" }
  postgres = { namespace = "postgres" }
}
```

The key is the S3 bucket name. `namespace` is the only namespace whose pods may read the resulting credentials.

Per entry, one apply produces:

| Object | Where |
| --- | --- |
| `aws_s3_bucket` `<bucket>` | SeaweedFS |
| `aws_iam_user` `<namespace>-<bucket>` | SeaweedFS |
| `aws_iam_access_key` for that user, non-expiring | SeaweedFS |
| `aws_iam_user_policy` `<bucket>-read-write`: `s3:*` on `arn:aws:s3:::<bucket>` and `arn:aws:s3:::<bucket>/*` | SeaweedFS |
| KV entry `seaweedfs/<namespace>/<bucket>` — `bucket`, `endpoint`, `region`, `access_key_id`, `secret_access_key` | OpenBao |
| Policy `seaweedfs-<namespace>-<bucket>`, `read` on that one path | OpenBao |

Plus one Kubernetes auth role per *namespace*, `seaweedfs-<namespace>`, bound to
`bound_service_account_namespaces = [<namespace>]` and carrying every policy for
that namespace's buckets. Service accounts are bound as `*`: any pod in the
namespace, nothing outside it.

Buckets carry no size limit — see
[SeaweedFS on s3-01](../s3-01/seaweedfs.md#no-bucket-quotas).
