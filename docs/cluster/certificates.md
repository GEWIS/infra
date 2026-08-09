# Certificates

cert-manager issues a single wildcard, `*.cbc.gewis.nl`, into the `traefik`
namespace, referenced both by the Gateway listener and by `tlsStore.default` so
it is the default certificate for classic IngressRoutes too.

`--dns01-recursive-nameservers-only` is required on campus, which blocks direct
queries to authoritative nameservers.

A dedicated subdomain matters. `fleet-infra` already issues `*.gewis.nl` from the
same Cloudflare zone; two cert-managers writing `_acme-challenge.gewis.nl` would
race and can break the other cluster's renewals. `*.cbc.gewis.nl` challenges at
`_acme-challenge.cbc.gewis.nl` instead — no collision.

Expect the first issue to be slow. cert-manager's self-check queries the campus
resolver, which caches the pre-creation `NODATA` answer for the zone's SOA
minimum (1800 s). The challenge sits in `pending` with *"not yet propagated"* for
up to 30 minutes and then completes on its own. `presented=true` on the Challenge
with no Cloudflare API errors means the record was written and the wait is purely
cache expiry.

Let's Encrypt caps duplicate certificates at 5/week for an identical name set.
Save `wildcard-cbc-gewis-nl-tls` and restore it into a rebuilt cluster: cert-manager
adopts a valid existing secret and issues nothing.
