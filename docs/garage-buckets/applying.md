# Applying

```sh
cd terraform/garage-buckets
tofu init
tofu plan
tofu apply
```

The access key's secret is revealed by Garage **only at creation**, so it lives
in the state file from then on. The state is PBKDF2 → AES-GCM encrypted with
`enforced = true` before it leaves the machine, same as every other root here.

Removing an entry from the map destroys the bucket. Garage refuses to delete a
non-empty bucket, so that fails the apply rather than eating data — but do not
lean on it as a safety net for a bucket you emptied yesterday.

Rotating a key means replacing the `garage_key` resource, which changes the
secret in OpenBao. Consumers break until External Secrets resyncs, which is
within its refresh interval, not instantly.
