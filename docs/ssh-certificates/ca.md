# The CA and the role

The CA key is **generated inside OpenBao** (`generate_signing_key = true`, ed25519)
and cannot be read out of it — not by an admin, not by OpenTofu. Losing OpenBao's
storage therefore means a new CA on the next apply. Hosts pick the new public key up
on their next [fetch](hosts.md), within fifteen minutes, and certificates signed by
the old one stop working; at a five-hour lifetime that costs one re-sign.

The `admin` signing role:

| Setting | Value | Why |
| --- | --- | --- |
| `allowed_users` | `root,cbc` | the accounts that exist on the hosts; no default, so the caller always names one |
| `ttl`, `max_ttl` | `5h` | expiry replaces revocation |
| `allowed_extensions` | `permit-pty` | an interactive shell and nothing else — no forwarding |
| `key_id_format` | `{{token_display_name}}` | `oidc-<username>` for an OIDC login; OpenBao does not allow identity templates here |

The policy `ssh-sign-admin` grants `update` on `ssh/sign/admin` and nothing more.
`50_authentik-config` attaches it to the OIDC role by name, so the two roots can be
applied in either order: until the policy exists, tokens simply lack it.
