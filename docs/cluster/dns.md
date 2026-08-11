# DNS

external-dns watches `gateway-httproute` and writes to Cloudflare.

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
hostname being retired, such as the Gateway API CRDs being replaced, which takes
every `HTTPRoute` with them. Recreating the record afterwards is not symmetric:
the `gewis.nl` SOA minimum is **1800 s**, so every downstream resolver serves
NODATA for up to half an hour after the name comes back, and the CNAME is correct
in Cloudflare the whole time. A stale record left behind by a retired route is
cheap in comparison — it is deletable by hand, and its ownership TXT says which
cluster wrote it.

The DNS target is the `external-dns.alpha.kubernetes.io/target` annotation on the
**Gateway**, not on each route — external-dns reads that override from the
Gateway only, and ignores it on an HTTPRoute. It is set once in
`flux/config/gateway/gateway.yaml`, so every route inherits it. The target is a
hostname, so records are CNAMEs. Without it external-dns would publish the
`Gateway`'s own addresses, which in host network mode are the node addresses
rather than one stable LoadBalancer address.

`--cloudflare-record-comment` tags every managed record; ownership itself is
still the TXT, not the comment.
