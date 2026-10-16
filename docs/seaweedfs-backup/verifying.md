# Verifying

After applying `terraform/40_seaweedfs-buckets` and `terraform/10_s3-01`.

## The opt-out tags are set

From `terraform/40_seaweedfs-buckets`, whose `.envrc` exports the admin keys as
`TF_VAR_seaweedfs_admin_*`. The `aws` CLI reads `AWS_*`, which in that shell
already hold your Scaleway key for the state backend, so pass the SeaweedFS keys
per call instead of exporting them:

```sh
tofu output -json buckets | jq 'map_values(.backup)'

sw() {
  AWS_ACCESS_KEY_ID="$TF_VAR_seaweedfs_admin_access_key" \
  AWS_SECRET_ACCESS_KEY="$TF_VAR_seaweedfs_admin_secret_key" \
  aws --endpoint-url http://s3.net.gewis.nl:8333 --region us-east-1 "$@"
}
sw s3api get-bucket-tagging --bucket loki   # no_backup=true
sw s3api get-bucket-tagging --bucket kaneo  # NoSuchTagSet
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

From a LAN address or a pod this answers. Over s3-01's own mesh address
(interface `nb-gewis`) it must not: the rule admits sources in `10.82.50.0/24`
only. Through the NetBird route to `10.82.50.0/24` it depends on that route,
which is configured in NetBird, not here: if the routing peer masquerades, which
is NetBird's default, the request arrives from a LAN address and is answered.
In Grafana, `up{job="s3-01"}` should be `1` and
`seaweedfs_backup_last_run_success{job="s3-01"}` should be `1`.

## The job key cannot touch the lock

With the job's key, against Scaleway:

```sh
export AWS_ACCESS_KEY_ID="$(sops -d --extract '["scaleway-backup-access-key"]' secrets/s3-01.yaml)"
export AWS_SECRET_ACCESS_KEY="$(sops -d --extract '["scaleway-backup-secret-key"]' secrets/s3-01.yaml)"
export AWS_DEFAULT_REGION=nl-ams AWS_ENDPOINT_URL=https://s3.nl-ams.scw.cloud
export AWS_REQUEST_CHECKSUM_CALCULATION=when_required

aws s3api put-object-lock-configuration --bucket gewis-seaweedfs-backup \
  --object-lock-configuration '{"ObjectLockEnabled":"Enabled","Rule":{"DefaultRetention":{"Mode":"GOVERNANCE","Days":30}}}'
  # must fail: AccessDenied
aws s3api list-object-versions --bucket gewis-seaweedfs-backup --max-items 1
  # must fail: AccessDenied (s3:ListBucketVersions is not granted)
```

Both are safe to run: the lock configuration is the one the bucket already has,
and listing changes nothing. Do not test a version delete with the job's key:
if the policy were wrong, any version past its 30 days would be gone. Instead,
with your own key, read the policy back and check that the job's statements
name only `s3:ListBucket`, `s3:GetObject`, `s3:PutObject`, `s3:DeleteObject`
and `s3:AbortMultipartUpload`:

```sh
aws s3api get-bucket-policy --bucket gewis-seaweedfs-backup --query Policy --output text | jq .
```

The key lives on s3-01, so these checks are what stand between a compromised
s3-01 and the off-site history. If either command above succeeds, the
[bucket policy](scaleway.md#4-the-bucket-policy) is missing or wrong.
