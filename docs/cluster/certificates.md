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

cert-manager checks that a challenge record is visible before asking Let's
Encrypt to validate it. `--dns01-recursive-nameservers-only` is required on
campus, which blocks direct queries to authoritative nameservers.
`--dns01-recursive-nameservers` sends that check over DoH to Cloudflare's
resolvers, `1.1.1.1` and `1.0.0.1`, which serve the Cloudflare-hosted zones
fresh. The check does not go through kube-dns or the
[cluster resolver](resolver.md), whose caches keep the `NODATA` answer from the
first check, before the record exists, for the zone's SOA minimum (1800 s).

The old cluster issues the same `gewis.nl` and `gew.is` names from the same
Cloudflare zones, so both cert-managers write `_acme-challenge.gewis.nl` and
`_acme-challenge.gew.is`. That is safe: Cloudflare keeps several TXT records under
one name, Let's Encrypt accepts any of them, and cert-manager's cleanup deletes a
record only when its content matches its own token. The Cloudflare API token
needs DNS edit rights on both the `gewis.nl` and `gew.is` zones.

A challenge passes the self-check within a minute or two. The two names that
share a TXT name with their wildcard, `gewis.nl` and `gew.is`, are presented only
after the wildcard's challenge is done, so they add one more round. A challenge
stuck in `pending` with *"not yet propagated"* while `presented=true` and no
Cloudflare API errors means the record is written but `1.1.1.1` does not see it
yet:

```sh
dig +short @1.1.1.1 TXT _acme-challenge.gewis.nl
```

Let's Encrypt caps duplicate certificates at 5/week for an identical name set.
