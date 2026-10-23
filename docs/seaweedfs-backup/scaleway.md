# The Scaleway side

Done once, by hand, like the [state bucket](../s3-01/state.md#who-can-touch-the-state).
The repository does not use the Scaleway provider, and a Project, an IAM
application and its policy are not reachable over the S3 API, so OpenTofu has
nothing to drive them with.

## 1. A Project of its own

Create a Project `seaweedfs-backup` and note its ID. IAM permission sets stop at
Project scope, so a Project holding only this bucket is what makes the job's
grant effectively bucket-scoped — the same reasoning as `tf-state`.

Add a rule to the `tofu-operators` policy granting `ObjectStorageFullAccess` on
this Project, so operators can create the bucket below and restore from it.

## 2. The bucket

Object Lock can only be switched on when the bucket is created. Use your own
operator key; the `@<project id>` suffix overrides the key's preferred Project
for this call, which otherwise decides where a new bucket lands:

```sh
export AWS_ACCESS_KEY_ID="<your access key>@<seaweedfs-backup project id>"
export AWS_SECRET_ACCESS_KEY="<your secret key>"
export AWS_DEFAULT_REGION=nl-ams
export AWS_ENDPOINT_URL=https://s3.nl-ams.scw.cloud
export AWS_REQUEST_CHECKSUM_CALCULATION=when_required

aws s3api create-bucket --bucket gewis-seaweedfs-backup \
  --create-bucket-configuration LocationConstraint=nl-ams \
  --object-lock-enabled-for-bucket

aws s3api put-object-lock-configuration --bucket gewis-seaweedfs-backup \
  --object-lock-configuration '{"ObjectLockEnabled":"Enabled","Rule":{"DefaultRetention":{"Mode":"GOVERNANCE","Days":30}}}'

aws s3api put-bucket-lifecycle-configuration --bucket gewis-seaweedfs-backup \
  --lifecycle-configuration '{"Rules":[{"ID":"expire-old-versions","Status":"Enabled","Filter":{"Prefix":""},"NoncurrentVersionExpiration":{"NoncurrentDays":30},"Expiration":{"ExpiredObjectDeleteMarker":true},"AbortIncompleteMultipartUpload":{"DaysAfterInitiation":7}}]}'

aws s3api get-bucket-versioning --bucket gewis-seaweedfs-backup   # Status: Enabled
```

`AWS_REQUEST_CHECKSUM_CALCULATION` is the same AWS SDK quirk as
`skip_s3_checksum` in the backends: without it the CLI adds CRC32 trailers that
non-AWS stores may reject.

What the three settings do together:

| Setting | Effect |
| --- | --- |
| Versioning (forced on by Object Lock) | an overwrite or delete keeps the old version; `rclone --s3-version-at` restores any moment |
| Object Lock, Governance, 30 days | every version is undeletable for 30 days after it is written, unless the caller holds bypass rights |
| `NoncurrentVersionExpiration` 30 days | an old version disappears 30 days after it was replaced or deleted, which is always after its lock ran out |

So a file deleted from SeaweedFS stays restorable for 30 days, and Barman's own
30-day retention means Scaleway holds roughly 60 days of Postgres WAL.

### Governance, not Compliance

Compliance mode cannot be shortened or lifted by anyone, the Organization owner
included. That would also block erasing a person's files from the backup before
the 30 days are up, and enabling the lock is already irreversible. Governance
stops the job key, which has no bypass rights, while an operator with full
access can still remove a version deliberately.

## 3. The job's key

Create an IAM application `seaweedfs-backup-job` with one policy, scoped to the
`seaweedfs-backup` Project:

- `ObjectStorageBucketsRead`
- `ObjectStorageObjectsRead`
- `ObjectStorageObjectsWrite`
- `ObjectStorageObjectsDelete`

Not `ObjectStorageBucketsWrite` and not `ObjectStorageFullAccess`: the job must
not be able to change versioning, the lock or the lifecycle rules. Generate an
API key for the application with `seaweedfs-backup` as its preferred Object
Storage Project.

Add it to the host's sops file, which every admin can edit:

```sh
sops secrets/s3-01.yaml
```

```yaml
scaleway-backup-access-key: <application access key>
scaleway-backup-secret-key: <application secret key>
```

Do this **before** the next `tofu apply` of `terraform/10_s3-01`: sops-nix
checks at build time that every declared secret exists, so without these two
keys the s3-01 closure does not build (*"the key 'scaleway-backup-access-key'
cannot be found"*). `nix flake check` only evaluates hosts, so CI stays green
either way.

Rotating the key is a new API key, the two values replaced in
`secrets/s3-01.yaml`, an apply of `terraform/10_s3-01`, and deleting the old key.
