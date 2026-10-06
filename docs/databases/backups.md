# Backups

## Postgres: Barman Cloud plugin to SeaweedFS

CloudNativePG backs up through the **Barman Cloud plugin**, not the in-tree
`spec.backup.barmanObjectStore`, which is deprecated. Three objects make it up:

| Object | File | Does |
| --- | --- | --- |
| `ObjectStore` `postgres` | `flux/services/postgres/object-store.yaml` | bucket path, endpoint, credentials, retention, compression |
| `Cluster.spec.plugins` | `flux/services/postgres/cluster.yaml` | points at the `ObjectStore`, `isWALArchiver: true` for continuous WAL archiving |
| `ScheduledBackup` `postgres-daily` | `flux/services/postgres/object-store.yaml` | a base backup every day at 03:00, `method: plugin` |

Continuous WAL plus daily base backups give point-in-time recovery to any moment
inside the 30-day `retentionPolicy`. Retention is Barman's job, not a bucket
lifecycle rule: Barman knows which WAL a base backup still needs, a lifecycle
rule does not. `immediate: true` takes the first base backup as soon as the
`ScheduledBackup` exists, because archived WAL is useless without one.

The plugin runs in `cnpg-system` beside the operator, from the `controllers`
layer (`flux/controllers/cloudnative-pg/plugin-barman-cloud.yaml`). It talks to
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

## MariaDB: logical dumps

MariaDB is still design only. The plan is logical dumps to a SeaweedFS bucket:
the mariadb-operator `Backup` CRD does scheduled logical backups to S3, with a
`mariadb-dump` `CronJob` as the fallback. `mariadb-dump` needs
`--single-transaction` for a consistent InnoDB snapshot without locking; that only
holds if every table is InnoDB and no DDL runs during the dump.
