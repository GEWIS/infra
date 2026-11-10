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
| `preferred_username` | the zot user, and the `docker login` username |
| `groups` | zot groups: the AD groups the user is a direct member of, see [Keycloak](../keycloak/index.md#oidc-clients) |

| Who | May |
| --- | --- |
| direct members of `CBC - Application Hosting Team (ADM)` | everything, including `delete` (`adminPolicy`) |
| an app's `group` from [app access](../cluster/app-access.md) | `read`, `create`, `update`, `delete` under `<app>/`: push with an API key, delete tags in the UI |
| any other logged-in user | `read` (`defaultPolicy`) |
| nobody logged in | nothing |

An app's images live under `<app>/`, its `name` in the app-access list.
`zot-values` gives the group `<app>/**` and repeats the policy on every
published path under it, see [The config](config.md).

## API keys

Logged-in users create API keys in the UI, optionally limited to repositories
and with an expiry, and use them as the password of
`docker login registry.gewis.nl -u <username>`. A key only works with its
owner's username and carries its owner's rights. Keys, like the rest of zot's
metadata, live in BoltDB on the PVC, see [Storage](storage.md). Only the UI can
create, list and revoke them, see
[Sessions and keys](sessions.md#key-management-refuses-header-credentials).

## Sessions

Sessions come only from the Keycloak login, see
[Sessions and keys](sessions.md#header-credentials-never-become-sessions). The
session cookie is signed and encrypted with `session-keys.json` from the Secret
`zot-session`, so sessions survive a restart. The Secret is generated once in
the cluster by an External Secrets `Password` generator with
`refreshPolicy: CreatedOnce`: a 64-character `hashKey` and an `encryptKey` cut
to 32 characters, the AES-256 key length, as zot uses the strings as raw bytes.
Deleting the Secret generates new keys and logs everyone out.
`secureSession: true` sets the cookie's `Secure` flag, as zot sees plain HTTP
behind Traefik.

The htpasswd file holds only `lan-reader`, see [LAN login](lan-login.md).
htpasswd users cannot log in with Docker clients: those follow the Bearer
challenge, and the token exchange accepts only API keys and GitHub tokens.
