# Restoring

Use your personal Scaleway key, which has `ObjectStorageFullAccess` on the
`s3-backup` Project, and the SeaweedFS admin keys that
`terraform/40_seaweedfs-buckets/.envrc` exports. From that directory:

```sh
export RCLONE_CONFIG_SCALEWAY_TYPE=s3
export RCLONE_CONFIG_SCALEWAY_PROVIDER=Scaleway
export RCLONE_CONFIG_SCALEWAY_REGION=nl-ams
export RCLONE_CONFIG_SCALEWAY_ENDPOINT=s3.nl-ams.scw.cloud
export RCLONE_CONFIG_SCALEWAY_ACCESS_KEY_ID="<your access key>@<s3-backup project id>"
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
rclone copy -v scaleway:gewis-s3-backup/<bucket> seaweedfs:<bucket>
```

`copy`, not `sync`: it never deletes on the SeaweedFS side.

## Encrypted buckets

A bucket with `backup_encrypt = true` ([Encryption per bucket](encryption.md))
is read back through crypt, rooted at its prefix. The keys are
`scaleway-backup-crypt-password` and `-salt` from `secrets/s3-01.yaml`, or the
copy in the admins' password manager:

```sh
export RCLONE_CRYPT_PASSWORD="$(sops -d --extract '["scaleway-backup-crypt-password"]' ../../secrets/s3-01.yaml | rclone obscure -)"
export RCLONE_CRYPT_PASSWORD2="$(sops -d --extract '["scaleway-backup-crypt-salt"]' ../../secrets/s3-01.yaml | rclone obscure -)"

rclone copy -v ":crypt,remote='scaleway:gewis-s3-backup/<bucket>':" seaweedfs:<bucket>
```

The file and directory name settings are rclone's defaults, which the job pins,
so they need no flags here. Everything else on this page applies unchanged, on
the underlying `scaleway` remote: `RCLONE_CONFIG_SCALEWAY_VERSION_AT` for
[a past moment](#the-bucket-as-it-was-at-a-moment), and the
[Glacier restore](#from-glacier) on `scaleway:gewis-s3-backup/<bucket>`,
which sees the encrypted names and restores all of them. A single file cannot
be picked out by name there; restore the whole prefix.

## From Glacier

A bucket with `backup_class = "GLACIER"` ([Storage class per
bucket](storage-class.md)) cannot be copied back until every object is
restored to `STANDARD`. Request that first, for long enough to finish the copy:

```sh
rclone backend restore scaleway:gewis-s3-backup/nextcloud -o lifetime=7
rclone backend restore-status scaleway:gewis-s3-backup/nextcloud
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
rclone copy -v scaleway:gewis-s3-backup/<bucket> seaweedfs:<bucket>
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
   [Glacier](#from-glacier) ones and through crypt for the
   [encrypted](#encrypted-buckets) ones, then
   `systemctl unmask --runtime seaweedfs-backup.timer` and
   `systemctl start seaweedfs-backup.timer`. The Glacier buckets are the slow
   part: start their restore first.
4. For Postgres, recover as in
   [Postgres from Scaleway](#postgres-from-scaleway); a cluster restored from
   this archive must archive under a new `serverName`.

## Postgres from Scaleway

A new CloudNativePG `Cluster` recovers the whole `postgres` cluster, every
database, from `s3://gewis-s3-backup/postgres/`. It reads the archive directly;
nothing in SeaweedFS is involved. The steps below build a throwaway cluster in
its own namespace, for a drill or to pull data out of. Replacing a lost
production cluster uses the same `bootstrap.recovery` and `externalClusters` in
place of `initdb` in `flux/40_services/postgres/cluster.yaml`, plus a new
`serverName` for its own archiving, see
[Postgres](../databases/postgres.md).

**1. Pick the target.** Without `recoveryTarget` the cluster recovers to the end
of the WAL in the copy. To match another bucket's copy, or to go back to before
a mistake, set `targetTime`, no later than the copy's newest WAL — see
[Point-in-time recovery off-site](pitr.md#what-scaleway-holds). A target past it
fails with *"recovery ended before configured recovery target was reached"*.

**2. Size and image.** The volume needs room for every database plus the WAL
being replayed; twice their size is safe. The image must have the major version
that wrote the archive. While production still runs:

```sh
kubectl -n postgres exec postgres-1 -c postgres -- psql -Atc \
  "select pg_size_pretty(sum(pg_database_size(datname))) from pg_database"
kubectl -n postgres get cluster postgres -o jsonpath='{.status.image}{"\n"}'
```

Longhorn refuses a volume that no node has room to schedule, even when the
nodes' disks are mostly empty: `kubectl -n longhorn-system get nodes.longhorn.io`
shows `storageScheduled` against `storageMaximum` per disk.

**3. Credentials.** With the `scaleway` remote from the top of this page
exported, put your key into a Secret without it reaching the command line or
the shell history. `printf` is a shell builtin, and `%@*` drops the Project
suffix, which only matters for creating buckets:

```sh
kubectl create namespace restore
kubectl -n restore create secret generic scaleway-restore --from-env-file=<(
  printf 'ACCESS_KEY_ID=%s\nSECRET_ACCESS_KEY=%s\nREGION=nl-ams\n' \
    "${RCLONE_CONFIG_SCALEWAY_ACCESS_KEY_ID%@*}" "$RCLONE_CONFIG_SCALEWAY_SECRET_ACCESS_KEY")
kubectl -n restore get secret scaleway-restore -o json \
  | jq -r '.data | to_entries[] | "\(.key) \(.value | @base64d | length)"'   # no length 0
```

**4. The cluster.** Through the NetBird proxy `kubectl apply` needs
`--validate=false` ([App access](../cluster/app-access.md#kubectl-over-netbird)),
so read the objects back afterwards:

```sh
kubectl apply --validate=false -f - <<'EOF'
apiVersion: barmancloud.cnpg.io/v1
kind: ObjectStore
metadata: { name: scaleway-postgres, namespace: restore }
spec:
  configuration:
    destinationPath: s3://gewis-s3-backup/postgres/
    endpointURL: https://s3.nl-ams.scw.cloud
    s3Credentials:
      accessKeyId:     { name: scaleway-restore, key: ACCESS_KEY_ID }
      secretAccessKey: { name: scaleway-restore, key: SECRET_ACCESS_KEY }
      region:          { name: scaleway-restore, key: REGION }
    wal: { compression: gzip }
  instanceSidecarConfiguration:
    env:
      - { name: AWS_REQUEST_CHECKSUM_CALCULATION,  value: when_required }
      - { name: AWS_RESPONSE_CHECKSUM_VALIDATION, value: when_required }
---
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata: { name: restore, namespace: restore }
spec:
  instances: 1
  imageName: <image from step 2>
  storage: { storageClass: longhorn-single, size: <size from step 2> }
  bootstrap:
    recovery:
      source: origin
      recoveryTarget:                      # omit to recover to the end of the copy
        targetTime: "<YYYY-MM-DD HH:MM:SS+00>"
  externalClusters:
    - name: origin
      plugin:
        name: barman-cloud.cloudnative-pg.io
        parameters:
          barmanObjectName: scaleway-postgres
          serverName: postgres
EOF
kubectl -n restore get cluster restore -o jsonpath='{.spec.bootstrap.recovery}{"\n"}'
kubectl -n restore get cluster restore -w        # until "Cluster in healthy state"
```

The cluster has no `plugins` entry with `isWALArchiver`, so it never writes to
Scaleway. Recovery runs in a job pod, `restore-1-full-recovery-<suffix>`:

```sh
kubectl -n restore get pods
kubectl -n restore logs <that pod> -c full-recovery | grep -oE '"message":"[^"]*recovery[^"]*'
kubectl -n restore logs <that pod> -c plugin-barman-cloud | grep '"level":"error"'
```

*"Unable to locate credentials"* from the plugin means an empty key in the
Secret. After fixing a failed recovery, delete the `Cluster` and apply it again
rather than waiting for the job's retries.

**5. Where it landed.** No Postgres function reports it once the cluster has
started, so read the newest row of a table the apps write often, which should
be just before the target:

```sh
kubectl -n restore exec restore-1 -c postgres -- psql -d <database> -Atc "<query>"
```

**6. Clean up** the same day; the namespace holds a copy of every database and
your key:

```sh
kubectl delete namespace restore
kubectl get pv | grep restore        # nothing left
```

## An app: files and database at one moment

An app that keeps files in a bucket and their index in Postgres comes back
consistent only if both are taken at the same moment. Mattermost is the example
here; Nextcloud has the same shape plus the [Glacier](#from-glacier) step.

1. **Find the run.** On s3-01, the moment the run listed the app's bucket:

   ```sh
   journalctl -u seaweedfs-backup --since <day> -o short-iso-precise | grep -E 'syncing (mattermost|postgres)'
   ```

   Every file the app referenced at that moment is in the copy.
2. **Recover Postgres** as [above](#postgres-from-scaleway), with `targetTime`
   no later than that moment *and* no later than the copy's newest WAL, which
   ends up to 5 minutes before `syncing postgres`.
3. **The files** from the same run. For the newest run nothing is needed; for an
   older one, set `RCLONE_CONFIG_SCALEWAY_VERSION_AT` to just after its
   `syncing <bucket>` line, see
   [the bucket as it was at a moment](#the-bucket-as-it-was-at-a-moment).
   Restoring means `rclone copy` through crypt into SeaweedFS, as in
   [Encrypted buckets](#encrypted-buckets); a drill copies only a sample to
   local disk, since `cryptcheck` already covers the content.
4. **Check they agree.** Every file the database references must be in the
   copy. For Mattermost the references are in `fileinfo`:

   ```sh
   MM=":crypt,remote='scaleway:gewis-s3-backup/mattermost':"
   kubectl -n restore exec restore-1 -c postgres -- psql -d mattermost -Atc "
     select path from fileinfo where deleteat = 0
     union select thumbnailpath from fileinfo where deleteat = 0 and thumbnailpath <> ''
     union select previewpath   from fileinfo where deleteat = 0 and previewpath   <> ''" \
     | sort -u > /tmp/restore-db.txt
   rclone lsf -R --files-only --fast-list "$MM" | sort > /tmp/restore-files.txt
   comm -23 /tmp/restore-db.txt /tmp/restore-files.txt | wc -l   # referenced but missing: must be 0
   ```

   A missing file created before the target is a gap in the backup; one created
   after it means the target was too late. Files in the copy that nothing
   references are normal.

   For Mattermost, the newest `jobs.createat` shows where the database landed
   (step 5 above); posts may be days older on a quiet instance.
5. **Clean up** the namespace as above, and delete local copies:
   `rm -f /tmp/restore-db.txt /tmp/restore-files.txt`, plus any sample. They
   hold people's files and file names.

## A restore drill

A copy is only proven by restoring it. Cheap checks first:

```sh
rclone check --one-way seaweedfs:kaneo scaleway:gewis-s3-backup/kaneo
rclone copy scaleway:gewis-s3-backup/kaneo /tmp/restore-kaneo
rclone cryptcheck --one-way seaweedfs:mattermost ":crypt,remote='scaleway:gewis-s3-backup/mattermost':"
```

`cryptcheck` encrypts each source file with the nonce from its copy's 32-byte
header and compares the result, so it proves both the copy and the keys while
downloading only the headers. That is still a read, so it needs a bucket that
is not in Glacier, such as `mattermost`.

The real drill is [An app: files and database at one moment](#an-app-files-and-database-at-one-moment)
against a throwaway namespace: it proves the Postgres archive recovers off-site
and that the files it points at are in the copy.
