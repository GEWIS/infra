# Sessions

Sessions only come from the UI's Keycloak login and last at most two hours.
Credentials sent in an `Authorization` header never turn into one, so rotating
the `lan-reader` password ends all access made with it.

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
