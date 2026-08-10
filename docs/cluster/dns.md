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
| `policy: sync` | deletes only records it owns, when their route disappears |
| `txtPrefix: edns-` | keeps the ownership TXT off the CNAME's name, which Cloudflare forbids |

The DNS target is the `external-dns.alpha.kubernetes.io/target` annotation on the
**Gateway**, not on each route — external-dns reads that override from the
Gateway only, and ignores it on an HTTPRoute. It is set once in
`flux/config/gateway/gateway.yaml`, so every route inherits it. The target is a
hostname, so records are CNAMEs. Without it external-dns would publish the
`Gateway`'s own addresses, which in host network mode are the node addresses
rather than one stable LoadBalancer address.

`--cloudflare-record-comment` tags every managed record; ownership itself is
still the TXT, not the comment.
