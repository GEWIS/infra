# Credentials and reachability

Both endpoints are reachable directly, no tunnels:

| Endpoint | Default | Notes |
| --- | --- | --- |
| SeaweedFS S3 + IAM | `http://10.82.50.100:8333` | One port for both APIs; campus LAN only, the host has no WAN leg |
| OpenBao | `https://openbao.cbc.gewis.nl:8443` | Through the cluster gateway |

There is no separate admin port. SeaweedFS serves the S3 API and an
AWS-IAM-compatible API on 8333, and 8333 is the only port the host firewall
opens, so the `aws` provider's `iam`, `s3` and `sts` endpoints all point at the
same URL.

The root's own `.envrc` exports every credential, so there is nothing to pass by
hand:

- `TF_VAR_seaweedfs_admin_access_key` ← `sops -d --extract '["seaweedfs-admin-access-key"]' secrets/s3-01.yaml`
- `TF_VAR_seaweedfs_admin_secret_key` ← `sops -d --extract '["seaweedfs-admin-secret-key"]' secrets/s3-01.yaml`
- `TF_VAR_bao_jwt` ← `kubectl -n openbao create token openbao-admin --request-timeout=2s`

That JWT is the same ServiceAccount path `terraform/40_openbao-config` uses; the
root logs in at `auth/kubernetes/login` as the `admin` role. The token's TTL is
an hour, and the `.envrc` mints it on directory entry, so a long-idle shell needs a
`direnv reload` before an apply.

## The admin identity

The two admin keys are not a static config file. `seaweedfs-admin.service` on
s3-01 waits for the filer and then runs
`weed shell s3.configure -user admin -actions Admin -apply` with those keys,
creating one identity in the filer-backed credential store. Everything this root
does — creating buckets, users, keys and policies — is that identity exercising
the IAM API. It is the equivalent of the old cluster-wide admin token, and it is
the only credential that is provisioned outside OpenTofu.

Identities are **not** declared in a static `-s3.config` file on purpose: such a
file overrides the filer store outright, with no merging, which would silently
discard every key this root manages.

## How a bucket key is minted

`aws_iam_access_key` asks SeaweedFS's IAM API for a key pair for
`<namespace>-<bucket>`. The secret is returned **only at creation**, so from
then on it lives in the OpenTofu state, and in the OpenBao KV entry the same
apply writes. Nothing reads it back off the server.

From OpenBao it reaches workloads through External Secrets — see
[Reading it from the cluster](reading.md). Rotating a key means replacing the
`aws_iam_access_key` resource, which changes the secret in OpenBao; consumers
break until External Secrets resyncs, which is within its refresh interval, not
instantly.
