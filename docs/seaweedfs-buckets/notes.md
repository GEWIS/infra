# Notes

- **No data was migrated.** The previous store's on-disk format is unrelated to
  SeaweedFS's and no importer exists, so the buckets started empty and the host
  was rebuilt rather than migrated: the second disk is reformatted and mounted
  at `/var/lib/seaweedfs`. Loki, Mimir and Tempo retention therefore starts at
  the cutover, not 30 days before it. That was a deliberate trade: observability
  data is historical and rebuilds itself by accrual within the retention window.

- **One bucket per component is a simplification.** Mimir's docs recommend
  separate buckets for blocks, ruler and alertmanager rather than sharing one
  with prefixes. Loki and Tempo are fine on a single bucket each. Splitting Mimir
  later is three more map entries.

- **One copy of every object.** A single node, a single volume directory, no
  replication. Nothing in these buckets is backed up by being here.

- **Bucket names never appear in Nix.** That keeps this root authoritative, but
  a bucket created by hand over the S3 API is invisible to OpenTofu.

- **The state file holds live secrets.** `aws_iam_access_key` returns the secret
  once. Nothing can read it back off the server, so state encryption is load
  bearing, not hygiene.
