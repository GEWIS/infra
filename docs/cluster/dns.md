# DNS

external-dns watches Traefik's `IngressRoute`s (the `traefik-proxy` source) and
plain `Ingress`es (the `ingress` source), and writes to Cloudflare. It takes each
hostname from the `Host(...)` matchers in a route's rules, or from an Ingress's
`host` fields; a route without one, such as the outpost callback, publishes
nothing. The chart grants the RBAC for both sources itself. Only the
`traefik.io` API group is watched — the legacy `traefik.containo.us` group is off
by default. The `ingress` source exists for charts that ship their own Ingress,
such as [Sealed Secrets](sealed-secrets.md).

**`domainFilters` must name the Cloudflare zone**, not the subdomain in use. A
zone matches only if it equals the filter or is a subdomain of it, so
`cbc.gewis.nl` excludes the `gewis.nl` zone — external-dns then finds no zone to
write into and reports the very misleading *"All records are already up to date"*.
The filter is `gewis.nl`; scoping comes from ownership instead:

| Setting | Effect |
| --- | --- |
| `txtOwnerId: cbc-test` | only touches records carrying its own ownership TXT |
| `policy: upsert-only` | creates and updates its own records, never deletes them |
| `txtPrefix: edns-` | keeps the ownership TXT off the CNAME's name, which Cloudflare forbids |

**`upsert-only`, not `sync`.** Under `sync` a record disappears the moment its
route does — and a route can vanish for reasons that have nothing to do with the
hostname being retired, such as Traefik's CRDs being replaced, which takes every
`IngressRoute` with them. Recreating the record afterwards is not symmetric:
the `gewis.nl` SOA minimum is **1800 s**, so every downstream resolver serves
NODATA for up to half an hour after the name comes back, and the CNAME is correct
in Cloudflare the whole time. A stale record left behind by a retired route is
cheap in comparison — it is deletable by hand, and its ownership TXT says which
cluster wrote it.

The DNS target is the `external-dns.alpha.kubernetes.io/target` annotation on
**each `IngressRoute` and `Ingress`**, set to `router02.net.gewis.nl`. The target is a
hostname, so records are CNAMEs onto the router, which owns the public address;
Traefik's own address, `10.82.50.10`, is private and useless from outside. A new
route that forgets the annotation gets no usable record.

`--cloudflare-record-comment` tags every managed record; ownership itself is
still the TXT, not the comment.
