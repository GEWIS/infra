# Who is the server administrator

There is no OIDC path to `GrafanaAdmin`. `role_attribute_path` and
`allow_assign_grafana_admin` are deliberately absent, so GEWISWG accounts receive
organization roles and nothing more. Server administration belongs to the local
`admin` account from the SealedSecret.

The login form is therefore **hidden** (`disable_login_form: true`), and the UI is
GEWISWG-only. That is a deliberate choice, not an oversight: server-level
administration happens through `terraform/grafana-config`, not by clicking. The
local `admin` remains fully usable because `[auth.basic]` is untouched — basic
auth against the API keeps working, which is exactly how that tofu root
authenticates.

What this costs: nothing reachable in the browser can administer the server. No
organization list, no user administration, no server settings. If a task has no
tofu resource, it is a `curl` against the API, or a temporary revert of this one
line.

If OIDC itself breaks — authentik unreachable, Active Directory down, the client
secret rotated out from under the release — there is no interactive way in at
all. Recovery is to set `disable_login_form: false` in git and let Flux
reconcile, which takes about as long as a reconcile. The API remains reachable
with the admin credentials throughout, which is how `terraform/grafana-config`
keeps working while nobody can log in.

That chain is longer than it was under Keycloak: a login now depends on
authentik, which depends on its Postgres database, which depends on the cluster.
Directory outages take Grafana logins with them, because authentik keeps no
local password for a synced user.

`role_attribute_strict` is `true`. An account whose roles match no mapping entry
is refused outright rather than landing in the empty `Main Org.` as a Viewer, so
`Main Org.` stays empty and access is exactly what GEWISWG says it is.

That setting couples logins to the tofu root more tightly than it looks.
`ParseOrgMappingSettings` resolves every org name at evaluation time, and under
strict mode a **single** unresolvable name discards the whole mapping — not just
that entry — which denies every user, not only the one whose role is affected. So
the seven organizations must exist before this is enabled, and destroying or
renaming one breaks all logins at once. `tofu apply` is what keeps them alive.

If a change here does lock people out, the way back is to revert it in git and let
Flux reconcile. Resetting the admin password does not help when the form is
hidden, and an apply can still repair orgs and mappings over the API while the UI
is unusable.
