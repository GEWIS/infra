# Applying

```sh
cd terraform/40_seaweedfs-buckets
tofu init
tofu plan
tofu apply
```

## Provider configuration

SeaweedFS is not AWS, so the `aws` provider is pointed away from every AWS
discovery path:

```hcl
provider "aws" {
  region     = "us-east-1"
  access_key = var.seaweedfs_admin_access_key
  secret_key = var.seaweedfs_admin_secret_key

  s3_use_path_style           = true
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_region_validation      = true
  skip_requesting_account_id  = true

  endpoints {
    iam = var.seaweedfs_endpoint
    s3  = var.seaweedfs_endpoint
    sts = var.seaweedfs_endpoint
  }
}
```

All three endpoints are the same URL because SeaweedFS serves S3 and IAM on the
one port. Path-style is mandatory: there is no wildcard DNS for
`<bucket>.s3.net.gewis.nl`. The four `skip_*` flags stop the provider from calling
STS, the EC2 metadata service or the AWS region list — none of which exist here;
without them every plan fails before it reaches a resource. `us-east-1` is a
placeholder that clients must echo back, not a location.

The admin keys come from `.envrc` as `TF_VAR_seaweedfs_admin_access_key` and
`TF_VAR_seaweedfs_admin_secret_key`; see
[Credentials and reachability](credentials.md).

## State

The backend key is `seaweedfs-buckets/terraform.tfstate` in the `gewis-tfstate`
bucket on Scaleway (`https://s3.nl-ams.scw.cloud`, path-style, lockfile on).
State and plans are PBKDF2 → AES-GCM encrypted with `enforced = true` before
they leave the machine, same as every other root here — which matters more than
usual, because the access key secrets are only ever readable there.

## Consequences

Removing an entry from the map destroys the bucket. SeaweedFS will delete a
bucket that still has objects in it, so unlike the previous setup there is no
accidental safety net: check the bucket is empty first.
