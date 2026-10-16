# Verifying

After applying `terraform/40_seaweedfs-buckets` and `terraform/10_s3-01`.

## The opt-out tags are set

With the admin keys from `terraform/40_seaweedfs-buckets/.envrc`:

```sh
tofu output -json buckets | jq 'map_values(.backup)'
aws --endpoint-url http://s3.net.gewis.nl:8333 s3api get-bucket-tagging --bucket loki   # no_backup=true
aws --endpoint-url http://s3.net.gewis.nl:8333 s3api get-bucket-tagging --bucket kaneo  # NoSuchTagSet
```

## The job runs

On s3-01:

```sh
systemctl list-timers seaweedfs-backup.timer
systemctl start seaweedfs-backup
journalctl -u seaweedfs-backup -b
cat /var/lib/prometheus-node-exporter-text/*.prom
```

Each copied bucket logs `syncing <bucket>` followed by the objects copied, or
`There was nothing to transfer`; each opted-out one logs `skipping <bucket>:
tagged no_backup`. Then compare, with the remotes from [Restoring](restoring.md):

```sh
rclone check --one-way seaweedfs:postgres scaleway:gewis-seaweedfs-backup/postgres
```

## The cluster sees it

```sh
curl -s http://s3.net.gewis.nl:9100/metrics | grep seaweedfs_backup
```

From a LAN address or a pod this answers; from a NetBird peer outside
`10.82.50.0/24` it must not. In Grafana, `up{job="s3-01"}` should be `1` and
`seaweedfs_backup_last_run_success{job="s3-01"}` should be `1`.

## The lock holds against the job key

With the job's key (`sops -d --extract '["scaleway-backup-access-key"]'
secrets/s3-01.yaml` and the secret beside it), pick any version in the bucket
and try to destroy it:

```sh
aws s3api delete-object --bucket gewis-seaweedfs-backup --key <key> \
  --version-id <version> --bypass-governance-retention   # must fail: AccessDenied
```

The key lives on s3-01, so this check is what stands between a compromised
s3-01 and the off-site history. If it succeeds, `ObjectStorageObjectsDelete`
includes the bypass right and Governance mode protects nothing against that key;
only Compliance mode would. Whether Scaleway puts bypass in that permission set
has not been checked yet.
