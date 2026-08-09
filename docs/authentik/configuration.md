# Configuring authentik

`terraform/authentik-config` owns everything *inside* authentik: the Active
Directory source today, and the providers, applications and groups that relying
parties need as they arrive. The Flux tree only deploys the software.

The root has no credential of its own. It reads the bootstrap token out of the
`authentik-auth` Secret with the `kubernetes` provider and authenticates as
`akadmin`, exactly as `terraform/grafana-config` reads `grafana-auth`. That
couples the root to the cluster, which costs nothing it was not already paying:
authentik has to be up and reachable for an apply to do anything.

## Users come from Active Directory

The source mirrors the Keycloak federation that already exists, so both systems
resolve the same people from the same directory. Keycloak's configuration screen
does not map field-for-field onto authentik's, and four differences are
deliberate rather than oversights:

| Setting | Value | Why |
| --- | --- | --- |
| `server_uri` | `ldaps://ldaps.gewis.nl` | the only name the certificate is valid for |
| `start_tls` | `false` | the provider defaults it true, which on port 636 means TLS inside TLS |
| `object_uniqueness_field` | `objectSid` | authentik's documented default for AD; Keycloak's `objectGUID` is proven there, not here |
| `sync_users_password` | `false` | that flag writes passwords *back* to AD, and the bind account only reads |

**`ldaps.gewis.nl` is load-bearing.** The certificate carries
`CN=ldaps.gewis.nl` with SANs for `ldaps.gewis.nl` and `gewisdc03.gewis.nl` only,
so connecting to `gewiswg.gewis.nl` or a raw address fails hostname verification.
It is publicly trusted (Let's Encrypt), so no CA has to be distributed, and it
resolves from the pod network without a resolver entry.

Reachability is asymmetric and worth knowing before debugging: **the cluster can
reach AD on 636, a workstation on the mesh cannot.** Anything that has to talk to
the directory by hand runs from a pod.

Since `password_login_update_internal_password` is left at its default of
`false`, authentik never stores a local password for a directory user. Logins
bind against AD every time, so **an AD outage means nobody can log in** — the
correct posture for a directory-backed IdP, but not a surprise worth having
during one.

## Only privilege holders are synced

`user_object_filter` restricts the source to members of
`PRIV - Logon Keycloak GEWISWG`, matched through
`memberOf:1.2.840.113556.1.4.1941:` so nested groups count. Without it the source
would pull the entire directory.

That group is Keycloak's, which welds authentik's user set to Keycloak's: anyone
who may log into one may log into the other. A dedicated
`PRIV - Logon Authentik GEWISWG` would let them diverge, and swapping to it later
costs a filter change and a re-sync.

## The bind account is authentik's own

`svc-authentik@gewiswg.gewis.nl`, not the `svc-auth` account Keycloak binds with.
Sharing one credential between two systems means rotating it is an outage in the
other, and resetting it to find out is an outage in GEWIS SSO — which Grafana
still depends on.

It needs read on users and groups under `DC=GEWISWG,DC=GEWIS,DC=nl` and nothing
else: no privileged groups, and **not** a member of the logon privilege group,
which governs who is synced rather than who may bind.

## Its password is the one secret

```sh
sops secrets/authentik.yaml     # ad-bind-password: …
direnv reload
```

`secrets/authentik.yaml` is admin-readable, declared through
`nix/recipients.nix` — `.sops.yaml` is generated, so add the name there and run
`nix run .#sops-config` rather than editing it by hand. `.envrc` exports the
value as `TF_VAR_ad_bind_password` and says so when it cannot.

## Applying

```sh
cd terraform/authentik-config
tofu init
tofu apply
```

Then read the synced groups back, because their names are what any OpenBao or
Grafana mapping has to match character-for-character:

```sh
TOK=$(kubectl -n authentik get secret authentik-auth \
  -o jsonpath='{.data.AUTHENTIK_BOOTSTRAP_TOKEN}' | base64 -d)
curl -sS -H "Authorization: Bearer $TOK" \
  'https://authentik.cbc.gewis.nl:8443/api/v3/core/groups/?page_size=100' \
  | jq -r '.results[].name'
```

Transcribing them from ADUC instead is how a mapping silently matches nothing.

## The `groups` claim needs no custom mapping

authentik's built-in `profile` scope already emits it:

```python
"groups": [group.name for group in request.user.groups.all()],
```

So an OIDC relying party can key its authorisation off `groups` with the stock
scopes. Guides that add a bespoke scope mapping for this are working around
something that is not true here.
