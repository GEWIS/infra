# seaweedfs-backup

SeaweedFS on [s3-01](../s3-01/seaweedfs.md) is one copy on one disk. Once a day,
at 04:15 UTC, s3-01 itself copies every bucket that needs to survive losing it to
the Scaleway bucket `gewis-seaweedfs-backup` in `nl-ams`, one prefix per source
bucket:

```
s3://gewis-seaweedfs-backup/<bucket>/<key>
```

| Piece | Where | Does |
| --- | --- | --- |
| `no_backup` opt-out per bucket | `terraform/40_seaweedfs-buckets/main.tf` | becomes the bucket tag `no_backup=true`; every untagged bucket is copied |
| `backup_class` per bucket | `terraform/40_seaweedfs-buckets/main.tf` | becomes the bucket tag `backup_class=<class>`, the Scaleway storage class of that bucket's copy; see [Storage class per bucket](storage-class.md) |
| `seaweedfs-backup.service` + `.timer` | `nix/hosts/s3-01/seaweedfs.nix`, script in `seaweedfs-backup.sh` | `rclone sync` per bucket, daily at 04:15 UTC |
| Scaleway key | `secrets/s3-01.yaml`, keys `scaleway-backup-access-key` / `-secret-key` | the job's write access to the backup bucket |
| Scaleway Project, bucket, IAM application | by hand, see [The Scaleway side](scaleway.md) | versioning, Object Lock, lifecycle |
| Node exporter on s3-01 | `nix/hosts/s3-01/seaweedfs.nix` | host health plus the job's result, scraped by the cluster's Alloy |
| Alerts | `flux/50_apps/observability/mimir/rules.yaml` | see [Alerting](../observability/alerting.md#the-s3-backup-rules) |

## Why on s3-01 and not in the cluster

The copy depends on nothing but s3-01 and Scaleway: no OpenBao, External Secrets,
Flux or Traefik. It reads SeaweedFS over loopback, keeps running through a
cluster outage or a broken cluster layer, and a run missed while s3-01 was off
happens at its next boot (`Persistent=true`).

What that costs, deliberately:

- **The Scaleway key sits on the host that holds the data.** Whoever owns s3-01
  can delete the current copies too. Object Lock keeps every version for 30
  days, and the [bucket policy](scaleway.md#4-the-bucket-policy) keeps the
  job's key from changing the lock or deleting versions, which makes the checks
  in [Verifying](verifying.md#the-job-key-cannot-touch-the-lock) mandatory, not
  optional.
- **It reads SeaweedFS with the admin identity**, not a read-only one. The admin
  keys already live on this host, and root here reads every object regardless;
  a read-only key minted by OpenTofu would have to come out of OpenBao, which
  is in the cluster.
- **Changes land with `tofu apply` of `terraform/10_s3-01`**, not by Flux.
- **Alerting still runs in the cluster.** While the cluster is down nothing
  alerts, but nothing writes new data either.
