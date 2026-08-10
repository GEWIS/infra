# The cluster runs its own resolver

A second CoreDNS lives in the `dns` namespace as a DaemonSet on **hostPort 53**,
udp and tcp: every node answers on `10.82.50.10x:53`, so LAN hosts can use it
directly. In-cluster it is also a Service pinned to `10.96.0.53`.

**hostPort, not hostNetwork.** The pod keeps its own network namespace, so
`dnsPolicy: None` with `nameserver 127.0.0.1` makes it resolve through itself and
never through the node — the loop the campus resolver would otherwise close. A
`hostNetwork` pod would instead bind `0.0.0.0:53` in the host namespace and
contend with Talos's own host DNS resolver.

The namespace is labelled `pod-security.kubernetes.io/enforce: privileged`
because baseline forbids hostPort. Ingress needs no such label — its Envoy is
part of Cilium and runs in `kube-system`, which Talos leaves unenforced.

## Adding a record by hand

Static records go in the `hosts` block of `flux/services/dns/corefile.yaml`, one
per line, address first:

```
hosts {
    10.82.50.100 s3.gewis.nl
    fallthrough
}
```

**`fallthrough` is not optional.** Without it the plugin answers authoritatively
for *everything* it is asked and NXDOMAINs every name not listed — the entire
internet included. With it, only listed names are answered here and the rest
continue to the forwarders.

Reverse lookups come for free: `dig -x 10.82.50.100` returns `s3.gewis.nl`.
A listed name is also answered for LAN clients, not just pods, since they hit the
same resolver. `reload` picks up a new entry without a restart, though allow ~60s
for the ConfigMap to reach every node.

`s3.gewis.nl` is a name that exists nowhere else — the public `gewis.nl` zone has
no address for it — so this creates a name rather than shadowing one. Overriding a
*public* name is equally possible and considerably easier to regret: it applies to
every pod and every LAN client pointed here, and nothing upstream will hint that
the answer is local.

One caveat specific to this entry: **s3-01's address is not reserved.** It comes
from DHCP, which is why `docs/s3-01.md` leaves Garage's `root_domain` unset and
addresses buckets path-style. `10.82.50.100` is hardcoded here and in
`terraform/garage-buckets`, so both rot together if the lease moves. A DHCP
reservation, as the Talos nodes already have, is what makes this safe.

## Aliasing one name onto another

`hosts` only maps names to addresses. To point a name at another *name* — where
the target already resolves and may move — use `rewrite` instead:

```
rewrite stop {
    name exact postgres.cbc.gewis.nl kube.gewis.nl
    answer auto
}
```

`postgres.cbc.gewis.nl` is how in-cluster clients reach the Postgres NodePort.
`kube.gewis.nl` is a public record carrying all three node addresses, so the
alias tracks the nodes instead of pinning one, and the resolver can follow it
through its normal upstreams.

**`answer auto` is not optional.** Without it the reply carries `kube.gewis.nl`
as the owner name of the A records while the client asked for
`postgres.cbc.gewis.nl`, and stub resolvers are entitled to discard the mismatch.
`answer auto` rewrites the owner names back on the way out.

This is resolver-only, exactly like `s3.gewis.nl`: a workstation resolving
through campus DNS gets NXDOMAIN. Anything running off-cluster — `tofu`, for one
— has to use `kube.gewis.nl` directly.

## DNS4EU first, Quad9 behind it

```
forward . https://86.54.11.13 https://86.54.11.213 {
    tls_servername noads.joindns4.eu
    next SERVFAIL REFUSED
}
forward . https://9.9.9.9 https://149.112.112.112 {
    policy sequential
}
```

DNS4EU's *Protective Resolution with Ad blocking* — EU-funded, GDPR-bound, and it
null-routes ads to `0.0.0.0`. The profile publishes two IPv4 addresses that answer
under the same certificate, so one `tls_servername` covers the pair.

Addresses, never hostnames — and that is not merely prudence. CoreDNS *cannot*
take a hostname upstream over DoH: `parseAsHostEntry` accepts hostnames for
`dns://` and `tls://` only, so `forward . https://noads.joindns4.eu` fails to
parse, with or without a `resolver`.

`tls_servername` is load-bearing: DNS4EU's certificate carries no IP SAN, so
connecting to `86.54.11.13` verifies only against the name.

**Why Quad9 needs a stanza of its own.** That servername is *global to the
stanza*, so a provider with a different name cannot sit beside DNS4EU. Going
without it requires the upstream to ship IP SANs — Quad9 does, which is why it
needs no `tls_servername`, while Mullvad and DNS4EU both fail `curl` by IP with
*"no alternative certificate subject name"*. The construct that would have allowed
one mixed list is `tls://` with per-endpoint `%name`, and **853 is blocked
outbound from the cluster**: `dial tcp 86.54.11.13:853: i/o timeout`, straight
from the resolver's log. Hence two stanzas joined by `next`.

**Know exactly what that covers.** `next` fires only on a *returned* RCODE. If
DNS4EU is unreachable, *forward* returns SERVFAIL to the client directly and the
Quad9 stanza is never reached — a plugin error return does not continue the chain.

| DNS4EU failure | Who answers |
| --- | --- |
| SERVFAIL / REFUSED | Quad9, via `next` — measured 50–131ms |
| one address down | the other, in-stanza |
| both unreachable | nobody here; kube-system's `next` sends pods to campus DNS |

Quad9 filters malware, not ads, so ads are unblocked while it is carrying traffic.

`policy sequential` makes the order a preference rather than a spread.

**Do not add `failover`.** It looks right — retry the next upstream on SERVFAIL
rather than only on a dead socket — but when *every* upstream returns that RCODE
the retry loop resets its own counter at the end of the list and spins until the
5s deadline. Measured: `dnssec-failed.org` turns from a 164ms SERVFAIL into a
hang. `next` is the single-hop version and does not have this behaviour.

## Campus taxes the first TLS connection, and CoreDNS caps DoH at 2s

The resolver logs intermittent `Post "https://86.54.11.13:443/dns-query": context
deadline exceeded` — roughly **15% of uncached upstream queries**. Every one still
returns a correct answer via fallback, but it costs time.

It is not DNS4EU. The identical Corefile run from a workstation, against the same
two addresses, handles 40 sequential uncached names and a 60-query concurrent
burst with **zero timeouts**, p50 38ms, max 331ms — on par with Cloudflare and
better than AdGuard.

It is the campus network, and it is not specific to DNS. TLS handshake time from a
node, three tries per destination:

| destination | 1st | 2nd | 3rd |
| --- | --- | --- | --- |
| `noads.joindns4.eu` | **3144ms** | 81ms | 80ms |
| `registry.k8s.io` | **3107ms** | 92ms | 83ms |
| `github.com` | **failed** | 1063ms | 107ms |
| `dns.quad9.net` | 85ms | 80ms | 83ms |
| `cloudflare.com` | 156ms | 82ms | 96ms |

The first connection to a destination costs seconds and every one after it is
fast — the signature of a TLS-inspecting middlebox doing per-destination
first-contact analysis and caching the verdict. It taxes image pulls the same way;
`registry.k8s.io` is in that table for a reason.

Underneath that sits a constant CoreDNS does not expose:

```go
c := http.Client{ Transport: httpTransport, Timeout: 2 * time.Second }
```

`read_timeout` does not reach it — that knob feeds the UDP/TCP proxy. A 2s ceiling
under a ~3s first-connection tax means every cold connection is a guaranteed
timeout.

So the fix is to stop opening cold connections, which is `max_idle_conns`, not
`expire`. Go's transport already holds idle connections for 90s; the limit is how
*many*. From `setup.go`:

```go
httpTransport.MaxIdleConns        = f.maxIdleConns
httpTransport.MaxIdleConnsPerHost = f.maxIdleConns
```

The plugin defaults `max_idle_conns` to 0, and the README calls 0 "unlimited" —
but Go reads a zero `MaxIdleConnsPerHost` as `DefaultMaxIdleConnsPerHost`, which
is **2**. Two warm connections per upstream, so any concurrency beyond that opens
a cold one straight into the tax. Hence `max_idle_conns 32` on both stanzas.

Measured in-cluster over ~1140 lookups:

| workload | client-visible failures | upstream timeouts |
| --- | --- | --- |
| 300 sequential uncached | 0 | **0** — 50ms/name |
| 300 concurrent real names, cold pool | **0 / 300** | 58 |
| 300 concurrent real names, hot pool | **0 / 300** | 14 |
| 10 uncached, before the change | — | 7 (and ~700ms/name) |

Two things that table is saying. Sequentially the fix is total: 300 uncached names
with **zero** timeouts, against ~15% before. Under concurrency a burst can still
outrun the pool and pay the tax on several connections at once — but it warms,
which is why the same workload drops from 58 to 14 on the second pass.

And it never costs a lookup. **0 failures in 1140**, because a timed-out upstream
falls to the second address, then to Quad9. The timeouts are latency, not errors.
They split evenly across both DNS4EU addresses (67 vs 64), confirming it is
connection setup rather than one sick endpoint. No pod restarts throughout.

What remains is unavoidable here: a genuinely new destination still pays the tax
once, and the 2s cap still turns that into one retried query. If the campus
middlebox ever stops being a factor — a different site, or a different uplink —
this knob becomes harmless rather than load-bearing.

The escape hatch, should the tax get worse, is `/etc/resolv.conf` as an upstream:
the university resolvers on plain 53 are permitted and pay no TLS tax at all. It
costs the ad-blocking for whatever they answer, and it needs the pod's
`dnsPolicy: None`/`nameserver 127.0.0.1` revisited first — as written, the pod's
own resolv.conf points at itself, so `forward . /etc/resolv.conf` would be a loop
and the `loop` plugin would refuse to start. Point it at the campus resolvers
explicitly instead.

## Internal-only `gewis.nl` names do not resolve through it

`gewiswg.gewis.nl` is delegated out of the Cloudflare zone to `gewisdc02` and
`gewisdc03`, which do not answer recursion from the internet, so every public
resolver SERVFAILs on it — and on `time.gewis.nl`, which is a CNAME into it.

A `forward gewis.nl` stanza pointed at those two domain controllers was tried and
removed: **they are unreachable from the pod network**. `nslookup time.gewis.nl
131.155.70.14` from inside a pod times out, which fits the campus rule that
blocks port 53 to anything that is not a university resolver — the very rule that
put this resolver on DoH in the first place. All the stanza achieved was a pair of
timeouts before falling through to an upstream that then hung trying to recurse
into the same unreachable servers.

Nothing in the cluster needs those names today. `time.gewis.nl` is Talos's NTP
server, and Talos resolves it on the **node**, against the node's own DHCP
resolvers — never through this resolver or through kube-system CoreDNS. If a
workload ever does need the AD zone, the fix belongs in the kube-system Corefile
as `forward gewis.nl /etc/resolv.conf`, which reaches the campus resolvers that
*are* permitted, rather than here.
