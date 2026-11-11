# The Scaleway side

## 1. A Project of its own

Create a Project `s3-backup` and note its ID. IAM permission sets stop at
Project scope, so a Project holding only this bucket is what makes the job's
grant effectively bucket-scoped, the same reasoning as `tf-state`.

Add a rule to the policy of the operators' IAM group `CBC-Infra` granting
`ObjectStorageFullAccess` on this Project, so operators can create the bucket
below and restore from it. Once the [bucket policy](#4-the-bucket-policy) is in
place, an operator also needs to be named in it.

## 2. The bucket

Create the bucket with Object Lock on; Scaleway can also switch it on for an
existing bucket, but never off again. Use your own
operator key; the `@<project id>` suffix overrides the key's preferred Project
for this call, which otherwise decides where a new bucket lands:

```sh
export AWS_ACCESS_KEY_ID="<your access key>@<s3-backup project id>"
export AWS_SECRET_ACCESS_KEY="<your secret key>"
export AWS_DEFAULT_REGION=nl-ams
export AWS_ENDPOINT_URL=https://s3.nl-ams.scw.cloud
export AWS_REQUEST_CHECKSUM_CALCULATION=when_required

aws s3api create-bucket --bucket gewis-s3-backup \
  --create-bucket-configuration LocationConstraint=nl-ams \
  --object-lock-enabled-for-bucket

aws s3api put-object-lock-configuration --bucket gewis-s3-backup \
  --object-lock-configuration '{"ObjectLockEnabled":"Enabled","Rule":{"DefaultRetention":{"Mode":"GOVERNANCE","Days":30}}}'

aws s3api put-bucket-lifecycle-configuration --bucket gewis-s3-backup \
  --lifecycle-configuration '{"Rules":[{"ID":"expire-old-versions","Status":"Enabled","Filter":{"Prefix":""},"NoncurrentVersionExpiration":{"NoncurrentDays":30},"Expiration":{"ExpiredObjectDeleteMarker":true},"AbortIncompleteMultipartUpload":{"DaysAfterInitiation":7}}]}'

aws s3api get-bucket-versioning --bucket gewis-s3-backup   # Status: Enabled
```

`AWS_REQUEST_CHECKSUM_CALCULATION` is the same AWS SDK quirk as
`skip_s3_checksum` in the backends: without it the CLI adds CRC32 trailers that
non-AWS stores may reject.

The console can create the bucket with Object Lock, show versioning and add
the lifecycle rule, but it cannot set the default retention: that one needs
`put-object-lock-configuration`. Without it Object Lock is on but locks
nothing, since the job never sets retention per object.

What the three settings do together:

| Setting | Effect |
| --- | --- |
| Versioning (forced on by Object Lock) | an overwrite or delete keeps the old version; [`RCLONE_CONFIG_SCALEWAY_VERSION_AT`](restoring.md#the-bucket-as-it-was-at-a-moment) restores any moment |
| Object Lock, Governance, 30 days | every version is undeletable for 30 days after it is written, unless the caller holds bypass rights |
| `NoncurrentVersionExpiration` 30 days | an old version disappears 30 days after it was replaced or deleted, which is always after its lock ran out |

So a file deleted from SeaweedFS stays restorable for 30 days, and Barman's own
30-day retention means Scaleway holds roughly 60 days of Postgres WAL.

### Governance, not Compliance

Compliance mode cannot be shortened or lifted by anyone, the Organization owner
included. That would also block erasing a person's files from the backup before
the 30 days are up, and enabling the lock is already irreversible.

Governance stops the job key: the bucket policy grants it neither
`s3:DeleteObjectVersion` nor bypass. An operator with `ObjectStorageFullAccess`
can still remove a locked version on purpose, which was tested on this bucket
before its bucket policy existed: a plain delete of a version is refused with
*"Access Denied because object protected by object lock"*, and the same call
with `--bypass-governance-retention` succeeds.

```sh
aws s3api delete-object --bucket gewis-s3-backup --key <key> \
  --version-id <version> --bypass-governance-retention
```

Operators keep this under the bucket policy through its `s3:*` grant;
[Verifying](verifying.md#the-job-key-cannot-touch-the-lock) checks it again.

## 3. The job's key

Create an IAM application `backup-s3` with one policy, scoped to the
`s3-backup` Project:

- `ObjectStorageObjectsRead`
- `ObjectStorageObjectsWrite`
- `ObjectStorageObjectsDelete`

Not `ObjectStorageBucketsRead` either: listing objects (`ListObjectsV2`) is in
`ObjectStorageObjectsRead`, and what the bucket set adds — `ListBuckets`,
`HeadBucket`, `GetBucketLocation` — the job never calls, since rclone runs with
`no_check_bucket` and is given the bucket by name.

These permission sets alone do not protect the lock: Scaleway puts
`PutObjectLockConfiguration`, `PutObjectRetention` and `PutObjectLegalHold` in
`ObjectStorageObjectsWrite`, and `DeleteObject` with a version ID in
`ObjectStorageObjectsDelete`. IAM cannot narrow a set below Project scope, so
the [bucket policy](#4-the-bucket-policy) does. Leaving out
`ObjectStorageBucketsWrite` and `ObjectStorageFullAccess` still keeps
versioning and the lifecycle rules out of the job's reach. Generate an
API key for the application with `s3-backup` as its preferred Object
Storage Project.

Add it to the host's sops file, together with the keys of the
[encrypted copies](encryption.md#the-keys):

```yaml
scaleway-backup-access-key: <application access key>
scaleway-backup-secret-key: <application secret key>
scaleway-backup-crypt-password: <output of openssl rand -base64 32>
scaleway-backup-crypt-salt: <output of openssl rand -base64 32>
```

Keep a copy of the two crypt keys in the admins' password manager too; without
them the encrypted copies cannot be read.

Do this **before** the next `tofu apply` of `terraform/10_s3-01`: sops-nix
checks at build time that every declared secret exists, so without these
keys the s3-01 closure does not build (*"the key 'scaleway-backup-access-key'
cannot be found"*). `nix flake check` only evaluates hosts, so CI stays green
either way.

Rotating the key is a new API key, the two values replaced in
`secrets/s3-01.yaml`, an apply of `terraform/10_s3-01`, and deleting the old key.

## 4. The bucket policy

Scaleway's policy version `2023-04-17` only allows: `Deny` statements do
nothing, and anyone not named is shut out of the bucket. Access is the
intersection of IAM and this policy, so it narrows the job to what
`rclone sync` uses, while operators keep everything:

```sh
cat >/tmp/backup-policy.json <<'EOF'
{
  "Version": "2023-04-17",
  "Id": "s3-backup",
  "Statement": [
    {
      "Sid": "Operators",
      "Effect": "Allow",
      "Principal": { "SCW": ["user_id:<operator user id>", "user_id:<operator user id>"] },
      "Action": "s3:*",
      "Resource": ["gewis-s3-backup", "gewis-s3-backup/*"]
    },
    {
      "Sid": "Job list",
      "Effect": "Allow",
      "Principal": { "SCW": "application_id:<backup-s3 application id>" },
      "Action": "s3:ListBucket",
      "Resource": "gewis-s3-backup"
    },
    {
      "Sid": "Job objects",
      "Effect": "Allow",
      "Principal": { "SCW": "application_id:<backup-s3 application id>" },
      "Action": ["s3:GetObject", "s3:PutObject", "s3:DeleteObject", "s3:AbortMultipartUpload"],
      "Resource": "gewis-s3-backup/*"
    }
  ]
}
EOF
aws s3api put-bucket-policy --bucket gewis-s3-backup --policy file:///tmp/backup-policy.json
```

What the job no longer gets, although its IAM sets include it:

| Action | Would let a compromised s3-01 |
| --- | --- |
| `s3:PutBucketObjectLockConfiguration` | drop or shorten the default retention, or switch it to Compliance for years |
| `s3:PutObjectRetention`, `s3:PutObjectLegalHold` | change the lock on single versions |
| `s3:DeleteObjectVersion` | destroy any version whose 30 days have run out, including the current copy of every object unchanged for a month |

`rclone sync` deletes without a version ID, which only places a delete marker
(`s3:DeleteObject`), so the job keeps working.

**Operators are named one by one.** A principal is a `user_id` or an
`application_id`, never a group, so the `Operators` statement repeats the
members of `CBC-Infra` by hand. A missing operator only lacks access to
this bucket, and a removed one stays locked out by IAM, so drift fails closed.
Look IDs up with `scw iam user list` and `scw iam application list`. Adding an
operator is a new `user_id` here and the `put-bucket-policy` again, see
[State](../s3-01/state.md#who-can-touch-the-state).

**Locking everyone out is possible:** a policy that names nobody, or names the
wrong IDs, leaves only the Organization Owner, who can always put or delete the
policy (`aws s3api delete-bucket-policy --bucket gewis-s3-backup`).
`s3:*` may not cover `PutBucketPolicy` for operators, since Scaleway lists no
such action; if `put-bucket-policy` fails for an operator, the Owner has to run
it. Both are unverified against Scaleway, as is the exact action set `rclone
sync` needs: the first run after the policy is the test, see
[Verifying](verifying.md#the-job-runs).
