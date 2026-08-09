# Credentials and reachability

Both endpoints are reachable directly, no tunnels:

| Endpoint | Default | Notes |
| --- | --- | --- |
| Garage Admin API | `http://10.82.50.100:3903` | Campus LAN only; the host has no WAN leg |
| OpenBao | `https://openbao.cbc.gewis.nl:8443` | Through the Traefik gateway |

`.envrc` exports both credentials, so there is nothing to pass by hand:

- `TF_VAR_garage_admin_token` ← `sops -d --extract '["garage-admin-token"]' secrets/s3-01.yaml`
- `TF_VAR_bao_jwt` ← `kubectl -n openbao create token openbao-admin`

That JWT is the same ServiceAccount path `terraform/openbao-config` uses; the
root logs in at `auth/kubernetes/login` as the `admin` role. The token's TTL is
an hour, and `.envrc` mints it on directory entry, so a long-idle shell needs a
`direnv reload` before an apply.

The Garage side authenticates with the master `admin_token` from
`/etc/garage.toml`, which grants every admin endpoint. Garage v2 supports scoped
tokens (`garage admin-token create --scope CreateBucket,…`) and that is the
better end state, but the token is printed exactly once at creation, so it is a
manual bootstrap rather than something this root can mint for itself.
