# Restoring

Use your personal Scaleway key, which has `ObjectStorageFullAccess` on the
`seaweedfs-backup` Project, and the SeaweedFS admin keys that
`terraform/40_seaweedfs-buckets/.envrc` exports. From that directory:

```sh
export RCLONE_CONFIG_SCALEWAY_TYPE=s3
export RCLONE_CONFIG_SCALEWAY_PROVIDER=Scaleway
export RCLONE_CONFIG_SCALEWAY_REGION=nl-ams
export RCLONE_CONFIG_SCALEWAY_ENDPOINT=s3.nl-ams.scw.cloud
export RCLONE_CONFIG_SCALEWAY_ACCESS_KEY_ID="<your access key>@<seaweedfs-backup project id>"
export RCLONE_CONFIG_SCALEWAY_SECRET_ACCESS_KEY="<your secret key>"

export RCLONE_CONFIG_SEAWEEDFS_TYPE=s3
export RCLONE_CONFIG_SEAWEEDFS_PROVIDER=SeaweedFS
export RCLONE_CONFIG_SEAWEEDFS_ENDPOINT=http://s3.net.gewis.nl:8333
export RCLONE_CONFIG_SEAWEEDFS_REGION=us-east-1
export RCLONE_CONFIG_SEAWEEDFS_STORAGE_CLASS=STANDARD
export RCLONE_CONFIG_SEAWEEDFS_ACCESS_KEY_ID="$TF_VAR_seaweedfs_admin_access_key"
export RCLONE_CONFIG_SEAWEEDFS_SECRET_ACCESS_KEY="$TF_VAR_seaweedfs_admin_secret_key"
```

Without `STORAGE_CLASS` on `seaweedfs`, rclone copies each source object's class
along with it, and objects restored from Glacier would be labelled `GLACIER` in
SeaweedFS.

## The latest copy

```sh
rclone copy -v scaleway:gewis-seaweedfs-backup/<bucket> seaweedfs:<bucket>
```

`copy`, not `sync`: it never deletes on the SeaweedFS side.

## From Glacier

A bucket with `backup_class = "GLACIER"` ([Storage class per
bucket](storage-class.md)) cannot be copied back until every object is
restored to `STANDARD`. Request that first, for long enough to finish the copy:

```sh
rclone backend restore scaleway:gewis-seaweedfs-backup/nextcloud -o lifetime=7
rclone backend restore-status scaleway:gewis-seaweedfs-backup/nextcloud
```

A restore can take up to 24 hours to start per object. A multipart object
counts as one object per part. Once `restore-status` shows nothing still in
progress, `rclone copy` as above. After `lifetime` days the objects go back to
Glacier by themselves.

These commands restore the current versions only. An older version, for
[the bucket as it was at a moment](#the-bucket-as-it-was-at-a-moment), needs
`aws s3api restore-object --version-id <version> --restore-request Days=7` per
object. Neither has been run against Scaleway yet.

## The bucket as it was at a moment

Versioning keeps every overwritten and deleted object for 30 days. Pin the
Scaleway remote to a point in time, which also makes it read-only:

```sh
export RCLONE_CONFIG_SCALEWAY_VERSION_AT="2026-10-10 12:00:00"
rclone copy -v scaleway:gewis-seaweedfs-backup/<bucket> seaweedfs:<bucket>
```

Set it on the `scaleway` remote only; the global `--s3-version-at` flag would
also make the SeaweedFS destination read-only.

## After losing s3-01

1. Rebuild the host ([Applying](../s3-01/applying.md)), then at once stop the
   backup on it until the restore is done:
   `systemctl mask --runtime --now seaweedfs-backup.timer`. Do this **before**
   the next step. It already skips empty buckets, see [The job](job.md), but
   once the buckets exist again Postgres archives WAL into the fresh `postgres`
   bucket within minutes and apps start writing. A run at 04:15 would then sync
   a bucket as it stands, and every object not yet copied back becomes a delete
   marker in Scaleway. The versions survive another 30 days, but there is no
   reason to need them. `--runtime` because `/etc/systemd/system` is read-only
   on NixOS; it lasts until the next boot, so repeat it after any reboot during
   the restore.
2. Apply `terraform/40_seaweedfs-buckets`. That recreates every bucket empty,
   with new keys that External Secrets picks up within the hour.
3. `rclone copy` each backed-up bucket back, as above, after restoring the
   [Glacier](#from-glacier) ones, then
   `systemctl unmask --runtime seaweedfs-backup.timer` and
   `systemctl start seaweedfs-backup.timer`. The Glacier buckets are the slow
   part: start their restore first.
4. For Postgres, recover as in [Backups](../databases/backups.md); a cluster
   restored from this archive must archive under a new `serverName`.

## A restore drill

A copy is only proven by restoring it. Two cheap checks and one real one:

```sh
rclone check --one-way seaweedfs:kaneo scaleway:gewis-seaweedfs-backup/kaneo
rclone copy scaleway:gewis-seaweedfs-backup/kaneo /tmp/restore-kaneo
```

The real one is a throwaway CloudNativePG `Cluster` with `bootstrap.recovery`
whose `ObjectStore` points straight at
`s3://gewis-seaweedfs-backup/postgres/` on `https://s3.nl-ams.scw.cloud` — it
proves the off-site copy is a usable Barman archive without touching SeaweedFS.
