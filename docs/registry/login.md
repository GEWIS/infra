# People log in through Keycloak

The UI is at `https://registry.gewis.nl`, reachable from anywhere. Its login
uses zot's generic `oidc` provider against
`https://auth.gewis.nl/realms/GEWISWG` with the `zot` client from
`oidc_clients` in `terraform/50_keycloak-config`, callback
`https://registry.gewis.nl/zot/auth/callback/oidc`. The `zot-oidc`
ExternalSecret reads `keycloak/zot/zot` and templates it into the
`credentials.json` zot expects.

| Claim | Becomes |
| --- | --- |
| `preferred_username` | the zot user |
| `groups` | zot groups: the AD groups the user is a direct member of, see [Keycloak](../keycloak/index.md#oidc-clients) |

| Who | May |
| --- | --- |
| direct members of `CBC - Application Hosting Team (ADM)` | everything, including `delete` (`adminPolicy`) |
| an app's `group` from [app access](../cluster/app-access.md) | `read`, `create`, `update`, `delete` under `<app>/`: delete tags in the UI; without API keys, nobody in the group can push |
| any other logged-in user | `read` (`defaultPolicy`) |
| nobody logged in | nothing |

An app's images live under `<app>/`, its `name` in the app-access list.
`zot-values` gives the group `<app>/**` and repeats the policy on every
published path under it, see [The config](config.md).

## No API keys

`apikey: false` turns zot's API keys off for everyone, admins included. zot
checks a key only against its own `meta.db`, never against Keycloak, and gives
it the groups its owner had at their last UI login. A person deleted from
Keycloak or removed from an app's group would keep those rights through any key
they hold, until it expires, and only they could revoke it. With keys off, zot
does not serve `/zot/auth/apikey` either. People manage tags in the UI; images
are pushed by [GitHub Actions](publishing.md).

## Sessions

Sessions come only from the Keycloak login, see
[Sessions](sessions.md#header-credentials-never-become-sessions). The
session cookie is signed and encrypted with `session-keys.json` from the Secret
`zot-session`, so sessions survive a restart. The Secret is generated once in
the cluster by an External Secrets `Password` generator with
`refreshPolicy: CreatedOnce`: a 64-character `hashKey` and an `encryptKey` cut
to 32 characters, the AES-256 key length, as zot uses the strings as raw bytes.
Deleting the Secret generates new keys and logs everyone out.
`secureSession: true` sets the cookie's `Secure` flag, as zot sees plain HTTP
behind Traefik.

The htpasswd file holds only `lan-reader`, see [LAN login](lan-login.md).
People cannot log in with Docker clients: those follow the Bearer challenge, and
the token exchange accepts only GitHub tokens.
