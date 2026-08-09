# Credentials

Read from the environment, never stored in tofu files and never committed.
Each operator holds their **own** Scaleway API key — these are personal
credentials, not a shared one, which is what makes offboarding work (see *Who
can touch the state*). Put them in `.envrc.local`, which is gitignored:

```sh
export XOA_TOKEN="<your XO token>"
export XOA_INSECURE=true    # only for a self-signed XO cert

export AWS_ACCESS_KEY_ID="<scaleway access key>"
export AWS_SECRET_ACCESS_KEY="<scaleway secret key>"
```

The XO endpoint itself is hardcoded in `terraform/s3-01/providers.tf`, not read from
`XOA_URL`, because a stray trailing newline in that variable trips the
provider's `malformed ws or wss URL` check.

The `AWS_*` names are not a mistake: the S3 backend speaks the AWS SDK, and
Scaleway's own `SCW_*` variables are read only by the Scaleway *provider*, which
this repo does not use. Scaleway documents exactly this re-export.
