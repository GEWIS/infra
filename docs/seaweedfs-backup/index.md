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
  can delete the current copies too. Object Lock is what still protects them,
  which makes the bypass check in [Verifying](verifying.md) mandatory, not
  optional.
- **It reads SeaweedFS with the admin identity**, not a read-only one. The admin
  keys already live on this host, and root here reads every object regardless;
  a read-only key minted by OpenTofu would have to come out of OpenBao, which
  is in the cluster.
- **Changes land with `tofu apply` of `terraform/10_s3-01`**, not by Flux.
- **Alerting still runs in the cluster.** While the cluster is down nothing
  alerts — but nothing writes new data either.

## What is copied

`postgres`, `mariadb`, `kaneo`, `nextcloud` and `mattermost`. The database
buckets already hold Barman and mariadb-operator backups with their own 30-day
retention, so copying them moves that point-in-time recovery off-site; the app
buckets hold the only copy of user files.

`loki`, `mimir` and `tempo` carry `no_backup`. Their data expires after 30 days
anyway and rebuilds by accrual, which is how the Garage cutover was handled too.

Any bucket without the tag is copied, including one created by hand outside
OpenTofu. Opting out is setting `no_backup = true` on its entry and applying
`terraform/40_seaweedfs-buckets`; the next run reads the tag. Nix names no
bucket. Opting out is for data that is cheap to lose, not for data that is large.

## Cost

Requests and ingress are free on Scaleway, so only stored bytes cost money. In
October 2026 the copied buckets held about 2 GB; with Postgres at a full 30-day
window and 30 days of old versions on top, the estimate was around 20 GB, about
€0.32 a month on Standard Multi-AZ. Growth of the `nextcloud` bucket is what
moves that number.
