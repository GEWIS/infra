# Storage class per bucket

Each bucket's copy lands in the Scaleway storage class its `backup_class` names
in `terraform/40_seaweedfs-buckets/main.tf`; unset is `STANDARD` (Multi-AZ), the
job's default:

| Bucket | Class | Why |
| --- | --- | --- |
| `nextcloud` | `GLACIER` | bulk user files, written once, read only in a full restore |
| everything else | `STANDARD` | read in place, or too small to matter |

`backup_class` becomes the bucket tag `backup_class=<class>`, read by
[the job](job.md) like `no_backup`. Allowed values are `STANDARD` and
`GLACIER`. Any other value fails that bucket's sync,
and with it the run.

## Why the database archives stay STANDARD

Glacier objects are listed but cannot be read until each one is restored, which
can take up to 24 hours to *start*. The `postgres` and `mariadb` copies are
complete Barman and mariadb-operator archives that a recovery reads in place
([Point-in-time recovery off-site](pitr.md)); in Glacier, losing both cluster
and s3-01 would add a day before recovery could begin, and every restore drill
would wait just as long. They are also small, so Glacier would save almost
nothing on them.

## What Glacier costs instead

- **Restoring takes a day or more.** See
  [Restoring](restoring.md#from-glacier). Nextcloud's database comes back from
  `STANDARD` first; files fail to open until the Glacier restore finishes.
- **One site.** Scaleway keeps all Glacier data in Paris DC4, even for a bucket
  in `nl-ams`, so this copy is not Multi-AZ.
- **Small files restore slowly.** Scaleway advises Glacier for objects over
  1 MB. Nextcloud's previews are small objects stored beside the files and
  share their `urn:oid:` naming, so no prefix can keep them out.
- **Restores are billed** per GB, on top of egress.
- **Not verified against Scaleway:** that Object Lock and the noncurrent-version
  lifecycle rule behave the same for Glacier objects as for `STANDARD` ones.

## Changing a bucket's class

The tag only decides the class of objects uploaded from then on. `--checksum`
compares MD5 and size, not class, so objects already in Scaleway keep theirs.

To move existing objects to Glacier, use your operator key with the remotes
from [Restoring](restoring.md):

```sh
rclone settier GLACIER scaleway:gewis-s3-backup/nextcloud
```

That rewrites each object as a new version. The old `STANDARD` version becomes
noncurrent and is billed until it expires, 30 days later.

Going back to `STANDARD` cannot be done by lifecycle rule or `settier`. Change
the tag, then restore the existing objects from Glacier permanently: in the
console, the *permanently* toggle on **Restore**.
