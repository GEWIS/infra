# The job

`seaweedfs-backup.service` on s3-01, a oneshot started by
`seaweedfs-backup.timer` every day at 04:15 UTC — after the 03:00 Postgres and
MariaDB base backups. The unit is declared in `nix/hosts/s3-01/seaweedfs.nix`;
the script it runs is `nix/hosts/s3-01/seaweedfs-backup.sh`, packaged with
`writeShellApplication`, so shellcheck runs on every build.

Per bucket SeaweedFS lists, it:

1. reads the bucket's tags (`GET /<bucket>?tagging`, signed with `curl
   --aws-sigv4`) and skips it if `no_backup=true` is set; no tags (`404
   NoSuchTagSet`) means copy it,
2. skips an empty bucket (below),
3. runs

```sh
rclone sync --fast-list --checksum --stats-one-line --stats 0 -v \
  "seaweedfs:$bucket" "scaleway:gewis-seaweedfs-backup/$bucket"
```

Both remotes are configured entirely through `RCLONE_CONFIG_<REMOTE>_*`
environment variables, so there is no rclone config file:

| Remote | Endpoint | Credentials |
| --- | --- | --- |
| `seaweedfs` | `http://127.0.0.1:8333`, region `us-east-1` | the admin identity, from the sops secrets `seaweedfs-admin-*` |
| `scaleway` | `s3.nl-ams.scw.cloud`, storage class `STANDARD` (Multi-AZ), `no_check_bucket` because the key may not create buckets | `scaleway-backup-*` from `secrets/s3-01.yaml` |

The secrets reach the unit as the sops template `seaweedfs-backup.env`
(`EnvironmentFile`, root-only). The unit runs as a `DynamicUser` with the same
hardening as the SeaweedFS units.

## Guards

- **No buckets listed** — SeaweedFS down or the key wrong — fails the run.
- **A bucket whose tags cannot be read** is not copied and fails the run.
- **A bucket whose objects cannot be listed** (`rclone size` exits non-zero) is
  not copied and fails the run.
- **A source bucket that lists no objects** is skipped and logged as
  `skipping <bucket>: no objects`; the run still succeeds. Syncing it would turn
  every object in its copy into a delete marker — exactly what would happen
  after s3-01 is rebuilt and the buckets come back empty. A new bucket is
  therefore simply not copied until its app writes the first object, and a
  bucket emptied in SeaweedFS keeps its last copy in Scaleway.

A bucket that fails is reported and the others still run; the unit exits
non-zero at the end. There is no automatic retry beyond rclone's own (3 attempts
per sync, 10 per request): the next attempt is the next day, or a manual
`systemctl start seaweedfs-backup`. `TimeoutStartSec=3h` stops a hung run.

## Incremental, not full

`sync` lists both sides and transfers only objects whose MD5 differs or that are
missing (`--checksum`; objects uploaded in parts carry no plain MD5 and fall back
to size). A run with nothing new logs `There was nothing to transfer` per
bucket. Scaleway does not charge for the listing requests.

Objects deleted from SeaweedFS are deleted in Scaleway too. With versioning on,
that only places a delete marker; the data stays restorable for 30 days, see
[The Scaleway side](scaleway.md#2-the-bucket).

## Metrics

`ExecStopPost` runs as root after every run, successful or not, and writes two
files into `/var/lib/prometheus-node-exporter-text`, which the node exporter's
textfile collector serves on `:9100`:

| Metric | Meaning |
| --- | --- |
| `seaweedfs_backup_last_run_timestamp_seconds` | when the last run ended |
| `seaweedfs_backup_last_run_success` | `1` if it succeeded, `0` if not |
| `seaweedfs_backup_last_success_timestamp_seconds` | when the last successful run ended; untouched by failures |

The cluster's Alloy scrapes `s3.net.gewis.nl:9100` as job `s3-01`; the firewall
admits 9100 from `10.82.50.0/24` only, where Cilium masquerades pod traffic to.
The alerts are in [Alerting](../observability/alerting.md#the-s3-backup-rules).

## Edges

- **Taking a bucket out of the backup** stops copying it but leaves its prefix
  in Scaleway. Delete that prefix by hand once it is no longer wanted.
- **Removing a bucket from the map** destroys it in SeaweedFS; the Scaleway copy
  is untouched, since the job no longer visits that prefix.
- **The first run** copies everything. At about 2 GB that is minutes. To seed
  without waiting a day: `systemctl start seaweedfs-backup` on s3-01.
- **Logs** are in the journal on s3-01 only — `journalctl -u seaweedfs-backup` —
  one line per transferred object. Nothing ships host logs to Loki.
