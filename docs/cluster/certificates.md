# Certificates

cert-manager issues a single wildcard, `*.cbc.gewis.nl`, into the `gateway`
namespace, where the Gateway listener references it by name. Same namespace, so
no `ReferenceGrant` is needed, and `cilium-operator` copies it into
`cilium-secrets` for Envoy to load over SDS.

`--dns01-recursive-nameservers-only` is required on campus, which blocks direct
queries to authoritative nameservers. It has to be paired with an explicit
`--dns01-recursive-nameservers=10.96.0.10:53`, because on its own it leaves the
self-check on the pod's `/etc/resolv.conf`. The cluster is dual-stack, `kube-dns`
holds both `10.96.0.10` and `fd00:cbc:1::a`, and a pod cannot reach the v6
ClusterIP — so the challenge sits in `pending` forever on

```
Waiting for DNS-01 challenge propagation:
  dial tcp [fd00:cbc:1::a]:53: connect: no route to host
```

`kube-dns` is the right target rather than the cluster's own resolver on
`10.96.0.53`: that one lives in the `services` layer, which waits on `config`,
which waits on this certificate.

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
