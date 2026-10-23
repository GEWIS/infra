# Sessions and keys

Sessions and API keys only come from the UI's Keycloak login. Credentials sent
in an `Authorization` header never turn into either, so revoking a key or
rotating the `lan-reader` password ends all access made with it.

## Header credentials never become sessions

zot answers a Basic login that carries `X-ZOT-API-CLIENT: zot-ui`, the UI's
marker, with a `session` cookie for that user. The cookie is not tied to the
hostname.

The `zot-no-session` Middleware in `flux/50_apps/zot/ingressroute.yaml` drops
`X-ZOT-API-CLIENT` from the request and every `Set-Cookie` from the response.
Every request on `zot-lan` passes through it, and so does every request with an
`Authorization` header on `registry.gewis.nl`. The public route's branch
without an `Authorization` header, which serves the UI and its Keycloak login,
does not.

## Key management refuses header credentials

zot lets any logged-in identity create API keys at `/zot/auth/apikey`, and a key
can create further keys. On `registry.gewis.nl`, requests to
`/zot/auth/apikey` with an `Authorization` header, whatever its value, match no
route and get the [fallback route's](../cluster/traefik.md) 404. A GitHub
Actions token, which only works from `main`, `master`, `develop` and `v*` tags,
or an existing key therefore cannot mint a key. The UI manages keys with its
session cookie; see [API keys](login.md#api-keys).
