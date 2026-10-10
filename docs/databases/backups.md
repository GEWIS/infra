# Backups

## Postgres: Barman Cloud plugin to SeaweedFS

CloudNativePG backs up through the **Barman Cloud plugin**, not the in-tree
`spec.backup.barmanObjectStore`, which is deprecated. Three objects make it up:

| Object | File | Does |
| --- | --- | --- |
| `ObjectStore` `postgres` | `flux/40_services/postgres/object-store.yaml` | bucket path, endpoint, credentials, retention, compression |
| `Cluster.spec.plugins` | `flux/40_services/postgres/cluster.yaml` | points at the `ObjectStore`, `isWALArchiver: true` for continuous WAL archiving |
| `ScheduledBackup` `postgres-daily` | `flux/40_services/postgres/object-store.yaml` | a base backup every day at 03:00, `method: plugin` |

Continuous WAL plus daily base backups give point-in-time recovery to any moment
inside the 30-day `retentionPolicy`. Retention is Barman's job, not a bucket
lifecycle rule: Barman knows which WAL a base backup still needs, a lifecycle
rule does not. `immediate: true` takes the first base backup as soon as the
`ScheduledBackup` exists, because archived WAL is useless without one.

The plugin runs in `cnpg-system` beside the operator, from the `controllers`
layer (`flux/20_controllers/cloudnative-pg/plugin-barman-cloud.yaml`). It talks to
the operator over mTLS with certificates from cert-manager, so its HelmRelease
depends on both. The `ObjectStore` CRD it installs therefore exists before
`services` declares one.

### The bucket and its credentials

The `postgres` bucket is one entry in `terraform/40_seaweedfs-buckets`, the same
flow as the LGTM buckets: OpenBao holds the key at `seaweedfs/postgres/postgres`
and an `ExternalSecret` syncs it into the `postgres-s3` Secret, region included.
Nothing secret is in git.

That makes `services` wait on the root: the `ExternalSecret` is not `Ready`
until `40_seaweedfs-buckets` has written the key, so on a fresh cluster apply it
while `services` is reconciling.

### Details that are easy to get wrong

- **`destinationPath` is the bucket, the server name is the cluster.**
  `serverName` is left empty, so Barman stores under `s3://postgres/postgres/`.
  Two clusters archiving to one prefix corrupt each other's WAL timeline, so a
  cluster restored *from* this one must archive under a new name.
- **CloudNativePG cron has six fields**, seconds first: `0 0 3 * * *` is 03:00.
- **Checksums:** current boto3 adds CRC32 checksums to every upload, which
  non-AWS stores can reject. `instanceSidecarConfiguration.env` sets
  `AWS_REQUEST_CHECKSUM_CALCULATION` and `AWS_RESPONSE_CHECKSUM_VALIDATION` to
  `when_required`.
- **Metrics are renamed** with the plugin, from `cnpg_collector_*` to
  `barman_cloud_cloudnative_pg_io_*`. Dashboards or alerts written for the
  in-tree path will not match.

### Longhorn stays out of it

Database volumes carry no Longhorn recurring jobs (see
[Postgres](postgres.md#database-volumes-opt-out-of-the-recurring-jobs)). A
Longhorn backup of a running database is only crash-consistent and duplicates
what Barman already keeps.

### What this does not cover

SeaweedFS is a single node on one disk, and
[`seaweedfs-buckets/index.md`](../seaweedfs-buckets/index.md) states plainly that
nothing in it is backed up by being there. These backups survive a lost cluster,
not a lost s3-01; an off-site copy of the bucket is what covers that.

A backup is only proven by a restore: recover into a throwaway `Cluster` with
`bootstrap.recovery` and an `externalClusters` entry pointing at the same
`ObjectStore` through the plugin.

## MariaDB: physical backups and binlog archiving

mariadb-operator gives the same shape as Barman: a base backup plus a continuous
log archive, both in SeaweedFS. All of it is in
`flux/40_services/mariadb/backup.yaml`:

| Object | Does |
| --- | --- |
| `PhysicalBackup` `mariadb-daily` | a `mariadb-backup` base backup every day at 03:00, `immediate: true`, from a replica when one is ready, kept 30 days (`maxRetention: 720h`) |
| `PhysicalBackup` `mariadb-replica` | never scheduled; the template the operator uses to rebuild or add a replica, written under `replica/` |
| `PointInTimeRecovery` `mariadb` | binary log archiving, referenced from the `MariaDB` by `pointInTimeRecoveryRef` |

The agent sidecar on the primary uploads each closed binary log. `max_binlog_size`
is 128M so a quiet database still closes logs often; the RPO is the time until
the current log closes or the next archive cycle. Recovery bootstraps a new
`MariaDB` with `bootstrapFrom.pointInTimeRecoveryRef` and a `targetRecoveryTime`.

All of them write to the `mariadb` bucket, under `base/`, `replica/` and `binlog/`. The `PhysicalBackup`s pass `--disable-ssl-verify-server-cert` to `mariadb-backup`, see [MariaDB](mariadb.md#tls). The bucket is an
entry in `terraform/40_seaweedfs-buckets`; its key reaches the `mariadb-s3`
Secret through an `ExternalSecret`, like `postgres-s3`.

### Details that are easy to get wrong

- **The binlog prefix must be empty when archiving starts.** A cluster restored
  from these backups must archive to a different prefix, or it writes on top of
  the timeline it came from.
- **Compression is fixed** once binary logs are archived: `gzip` for both
  objects.
- **Archive state is not a metric.** It is in `.status.pointInTimeRecovery` of the
  `MariaDB`:

  ```sh
  kubectl -n mariadb get mariadb mariadb -o jsonpath='{.status.pointInTimeRecovery}'
  ```

  The backup alerts watch the backup Jobs; nothing alerts on a stalled binlog
  archive.
- **The operator's cron has five fields**, unlike CloudNativePG's six.
