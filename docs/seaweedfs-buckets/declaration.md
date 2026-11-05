# The declaration

Everything is driven by one map, `local.buckets` in
`terraform/40_seaweedfs-buckets/main.tf`; the current buckets are listed there
and nowhere else. An entry looks like this:

```hcl
buckets = {
  loki     = { namespace = "observability", no_backup = true }
  postgres = { namespace = "postgres" }
}
```

The key is the S3 bucket name. `namespace` is the only namespace whose pods may read the resulting credentials.

`no_backup = true` keeps a bucket out of the daily off-site copy; every bucket
without it is copied. It becomes the bucket tag `no_backup=true`, which s3-01
reads at backup time, so the host carries no bucket names. See
[SeaweedFS backup](../seaweedfs-backup/index.md).

Per entry, one apply produces:

| Object | Where |
| --- | --- |
| `aws_s3_bucket` `<bucket>`, tagged `no_backup=true` if the entry opts out | SeaweedFS |
| `aws_iam_user` `<namespace>-<bucket>` | SeaweedFS |
| `aws_iam_access_key` for that user, non-expiring | SeaweedFS |
| `aws_iam_user_policy` `<bucket>-read-write`: object, list and multipart actions on `arn:aws:s3:::<bucket>` and `arn:aws:s3:::<bucket>/*`, nothing on its tags, policy or the bucket itself | SeaweedFS |
| KV entry `seaweedfs/<namespace>/<bucket>` — `bucket`, `endpoint`, `region`, `access_key_id`, `secret_access_key` | OpenBao |
| Policy `seaweedfs-<namespace>-<bucket>`, `read` on that one path | OpenBao |

Plus one Kubernetes auth role per *namespace*, `seaweedfs-<namespace>`, bound to
`bound_service_account_namespaces = [<namespace>]` and carrying every policy for
that namespace's buckets. Service accounts are bound as `*`: any pod in the
namespace, nothing outside it.

SeaweedFS folds each action into a coarse one: `GetObject` and `GetBucketLocation`
into Read, `PutObject`, `DeleteObject` and the multipart actions into Write,
`ListBucket` into List. Tagging, ACLs, `DeleteBucket` and Admin stay out, so an
app can neither retag its bucket (`no_backup=true` would silently drop it from
the [off-site copy](../seaweedfs-backup/index.md)) nor delete it. `s3:*` would
grant Admin. An app that needs object tags or ACLs needs those actions added.

Buckets carry no size limit — see
[SeaweedFS on s3-01](../s3-01/seaweedfs.md#no-bucket-quotas).
