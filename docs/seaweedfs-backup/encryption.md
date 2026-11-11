# Encryption per bucket

A bucket with `backup_encrypt = true` in `terraform/40_seaweedfs-buckets/main.tf`
is copied through [rclone crypt](https://rclone.org/crypt/), so Scaleway only
holds ciphertext. It is meant for user files, such as Nextcloud and Mattermost;
the map in `main.tf` says which buckets have it. The database archives stay
plain: Barman and mariadb-operator read them in place, see
[Point-in-time recovery off-site](pitr.md).

`backup_encrypt` becomes the bucket tag `backup_encrypt=true`, read by
[the job](job.md) like `no_backup` and `backup_class`. Any other value fails
that bucket's sync, and with it the run.

## What it does

The job syncs an encrypted bucket to an on-the-fly crypt remote rooted at the
bucket's prefix:

```sh
rclone sync --fast-list ... "seaweedfs:nextcloud" \
  ":crypt,remote='scaleway,storage_class=GLACIER:gewis-s3-backup/nextcloud':"
```

| Visible in Scaleway | Encrypted |
| --- | --- |
| the prefix (`nextcloud/`), the number of objects, their sizes (plus 32 bytes and 16 per 64 KiB), times and directory depth | contents, file names, directory names |

Each source object is still exactly one object in Scaleway, so versioning,
[Object Lock](scaleway.md#2-the-bucket), the lifecycle rules, the
[bucket policy](scaleway.md#4-the-bucket-policy) and the
[storage class](storage-class.md) apply unchanged, and
[restoring a past day](restoring.md#the-bucket-as-it-was-at-a-moment) works the
same way.

Encryption guards against anyone who can read the bucket at Scaleway. It does
not guard against a compromised s3-01, which holds the keys next to the data.

## Change detection

crypt objects carry no hash of the plaintext, so `--checksum` would silently
fall back to comparing size only and miss an edit that keeps the size. An
encrypted bucket is therefore compared by size and modification time. A
changed object is uploaded again with a plain PUT; the job never needs a
server-side copy, which an object already in Glacier could not serve.

## The keys

Two secrets in `secrets/s3-01.yaml`, in plain text; the job obscures them for
rclone at start:

```yaml
scaleway-backup-crypt-password: <output of openssl rand -base64 32>
scaleway-backup-crypt-salt: <output of openssl rand -base64 32>
```

Add both **before** the next `tofu apply` of `terraform/10_s3-01`, like the job
key in [The Scaleway side](scaleway.md#3-the-jobs-key): sops-nix will not build
the host without them. Without them at run time the encrypted buckets fail
with `tagged backup_encrypt but the crypt keys are missing`.

**Keep a second copy outside this repository**, in the admins' password
manager. sops is the only other place they exist, and without them every
encrypted copy is unreadable.

**Never change them**, nor `RCLONE_CRYPT_FILENAME_ENCRYPTION` and
`RCLONE_CRYPT_DIRECTORY_NAME_ENCRYPTION` in `nix/hosts/s3-01/seaweedfs.nix`.
Any of these changes every encrypted name: the next run uploads the whole
bucket again under new names, turns every old name into a delete marker, and
the old versions, readable only with the old keys, expire 30 days later. The
job has no rotation.

## Switching a bucket on or off

crypt skips objects under the prefix whose names do not decrypt (*"Skipping
undecryptable file name"*) and leaves them alone, so an existing plain copy
would stay current, and stored, forever. When a bucket that was already
copied switches to encryption, apply `terraform/40_seaweedfs-buckets`, then
before the next run remove the plain copy with your operator key and the
remotes from [Restoring](restoring.md):

```sh
rclone purge scaleway:gewis-s3-backup/nextcloud
```

That only places delete markers: the plain versions stay restorable for 30 days
and then expire. Switching encryption off is the same in reverse. If a run
comes first, purging still works; the next run then uploads everything again.
