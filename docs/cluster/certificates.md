# Certificates

cert-manager issues one certificate for every public hostname from the
`letsencrypt-prod` ClusterIssuer into the `traefik` namespace
(`flux/30_config/cert-manager/wildcard-cbc-certificate.yaml`):

| Name | Covers |
| --- | --- |
| `*.cbc.gewis.nl` | this cluster's own services |
| `gewis.nl`, `*.gewis.nl` | the apex and every service the old cluster publishes |
| `*.test.gewis.nl`, `*.personal.gewis.nl` | test and personal sites |
| `gew.is`, `*.gew.is` | the short domain |

It is one certificate: if any name fails to validate, none of them renew, and the
`config` layer stays un-`Ready` until it does. Traefik's default
`TLSStore` names the secret, `wildcard-cbc-gewis-nl-tls`, as its default
certificate, so every route with `tls: {}` serves it and no app namespace holds a
copy — see [Ingress](traefik.md).

The databases get certificates of their own from the same issuer, for exactly one
name each, so the wildcard key never leaves `traefik`:

| Certificate | Namespace | Name | Used by |
| --- | --- | --- | --- |
| `postgres-tls` | `postgres` | `postgres.net.gewis.nl` | [Postgres](../databases/postgres.md#tls-is-required-and-verified) |
| `mariadb-tls` | `mariadb` | `mariadb.net.gewis.nl` | [MariaDB](../databases/mariadb.md#tls) |

`--dns01-recursive-nameservers-only` is required on campus, which blocks direct
queries to authoritative nameservers. It leaves the self-check on the pod's
`/etc/resolv.conf`, which resolves to `kube-dns` — correct only because the cluster
is [single-stack](../talos/networking.md). A second family in `resolv.conf` sends
the check to a ClusterIP the nodes cannot route and the challenge never validates.

The old cluster issues the same `gewis.nl` and `gew.is` names from the same
Cloudflare zones, so both cert-managers write `_acme-challenge.gewis.nl` and
`_acme-challenge.gew.is`. That is safe: Cloudflare keeps several TXT records under
one name, Let's Encrypt accepts any of them, and cert-manager's cleanup deletes a
record only when its content matches its own token. The Cloudflare API token
needs DNS edit rights on both the `gewis.nl` and `gew.is` zones.

Expect the first issue to be slow. cert-manager's self-check queries the campus
resolver, which caches the pre-creation `NODATA` answer for the zone's SOA
minimum (1800 s). The challenge sits in `pending` with *"not yet propagated"* for
up to 30 minutes and then completes on its own. `presented=true` on the Challenge
with no Cloudflare API errors means the record was written and the wait is purely
cache expiry.

Let's Encrypt caps duplicate certificates at 5/week for an identical name set.
