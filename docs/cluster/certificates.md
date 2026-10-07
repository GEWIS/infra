# Certificates

cert-manager issues a single wildcard, `*.cbc.gewis.nl`, from the
`letsencrypt-prod` ClusterIssuer into the `traefik` namespace
(`flux/30_config/cert-manager/wildcard-cbc-certificate.yaml`). Traefik's default
`TLSStore` names the secret, `wildcard-cbc-gewis-nl-tls`, as its default
certificate, so every route with `tls: {}` serves it and no app namespace holds a
copy — see [Ingress](traefik.md).

`--dns01-recursive-nameservers-only` is required on campus, which blocks direct
queries to authoritative nameservers. It leaves the self-check on the pod's
`/etc/resolv.conf`, which resolves to `kube-dns` — correct only because the cluster
is [single-stack](../talos/networking.md). A second family in `resolv.conf` sends
the check to a ClusterIP the nodes cannot route and the challenge never validates.

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
