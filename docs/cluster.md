# cluster

What runs *inside* the Talos cluster, and how Flux orders it. The cluster itself
— VMs, machine config, CNI — is [`docs/talos.md`](talos.md).

Everything here is reconciled by Flux from `flux/`, with one `Kustomization` per
layer in `flux/clusters/gewis-prod/`.

## Layers exist to order CRDs and secrets, nothing else

```
crds ───────────┐
                ├─→ controllers ─→ config ─────→ services
sealed-secrets ─┘               └─→ openbao ───────┘
```

| Layer | Path | Holds |
| --- | --- | --- |
| `crds` | upstream `gateway-api` | Gateway API CRDs |
| `sealed-secrets` | `flux/sealed-secrets/` | the sealed-secrets controller |
| `controllers` | `flux/controllers/` | cert-manager, traefik, external-dns, longhorn, external-secrets |
| `config` | `flux/config/` | ClusterIssuer, wildcard Certificate, Longhorn jobs, the kube-system Corefile |
| `services` | `flux/services/` | the resolver, the LGTM stack, the node exporter |
| `openbao` | `flux/openbao/` | OpenBao, its HTTPRoute, its seal secret |

Three dependencies carry real weight and none is cosmetic:

- **`controllers` depends on `crds`** because Traefik's Helm chart renders a
  `Gateway` and `GatewayClass`. Those are custom resources; without the CRDs the
  *whole release* fails to install, not just the Gateway.
- **`controllers` depends on `sealed-secrets`** because it now applies
  `SealedSecret` objects, so the CRD and its decryptor must already exist.
- **`services` depends on `openbao`** because the observability stack reads its S3
  credentials through an `ExternalSecret`. External Secrets retries until OpenBao
  answers, so this is not a correctness requirement — but with `wait: true` the
  layer would otherwise sit un-`Ready` through the whole of OpenBao's first boot,
  which reads as a broken deploy rather than an ordered one.

SealedSecrets live next to the chart that consumes them rather than in a central
secrets directory. That works only because the decryptor is hoisted into its own
earlier layer: a SealedSecret in the *same* layer as the sealed-secrets
controller is a race, whereas one in a *later* layer decrypts within a second.

Do not put a secret in a layer that depends on the layer consuming it. external-dns
takes its Cloudflare token as a startup environment variable, so with its secret
in `config` the pod blocks on `CreateContainerConfigError` → the HelmRelease never
goes `Ready` → `controllers` never goes `Ready` → `config` never applies → the
secret is never created. A clean deadlock. cert-manager tolerates the same
placement only because its pods start fine without the token; it is read later,
at `Certificate` reconcile.

The `sealed-secrets` **namespace** is created by OpenTofu, not Flux, so the
sealing key can be pinned and survive a cluster rebuild — see
`terraform/talos-bootstrap/sealed-secrets.tf`.

## Gateway API is an add-on, and its version must match Traefik

Gateway API is **not** part of Kubernetes and nothing installs it by default —
not Talos, not the Traefik chart (which ships only `traefik.io` CRDs), and not
Cilium unless `gatewayAPI.enabled` is set. It is pulled from upstream by the
`crds` layer via a `GitRepository` pinned to a tag, so Renovate keeps it current;
vendoring the YAML would work too but Renovate cannot bump a static blob.

**Pin the version to what the controller wants, not to whatever is newest-looking.**
Traefik 3.7.5 watches `TLSRoute` and `BackendTLSPolicy` at `gateway.networking.k8s.io/v1`.
Gateway API v1.2.1 serves those at `v1alpha2`/`v1alpha3`, so its informers fail
with *"the server could not find the requested resource"* — indistinguishable
from the CRDs being absent. The provider then never syncs, so:

```
GatewayClass  Accepted=Unknown  "Waiting for controller"
Gateway       Programmed=Unknown
HTTPRoute     status: <empty>
```

and external-dns, which reads targets from an HTTPRoute's `status.parents`,
silently emits nothing. v1.6.1 serves both at `v1` and fixes it.

Use the **experimental** channel. Traefik watches those kinds regardless of the
chart's `experimentalChannel: false`, so the CRDs must exist either way; the
channel is a strict superset of standard.

Traefik does not rebuild its Gateway API informers after startup — installing the
CRDs under a running Traefik changes nothing until the pods restart.

## Routing is Gateway API, auth would be Traefik

Traefik is the Gateway API implementation (`gatewayClassName: traefik`) and the
chart creates a Gateway named `traefik-gateway` in the `traefik` namespace. That
name is hardcoded in the chart, not derived from the release name, so an
`HTTPRoute` can rely on it:

```yaml
parentRefs:
  - name: traefik-gateway
    namespace: traefik
```

Routing lives in portable `HTTPRoute` objects so the implementation can be
swapped later. Authentication cannot be portable: Gateway API has no auth filter,
and Cilium's Gateway API has no OIDC at all — the open request is cilium#31604.
The workarounds (hand-written `CiliumEnvoyConfig` with `ext_authz`, or a separate
`oauth2-proxy`) are fragile, so OIDC stays on Traefik `Middleware` attached via
`ExtensionRef`. That seam is the one deliberately non-portable part.

A Gateway HTTPS listener **requires** `certificateRefs`; unlike a classic Traefik
entrypoint it will not fall back to a self-signed certificate.

## Certificates

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

## DNS

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
Gateway only, and ignores it on an HTTPRoute. It is set once in the Traefik chart
values, so every route inherits it. The target is a hostname, so records are
CNAMEs; with hostPort there is no LoadBalancer address for external-dns to
discover on its own.

`--cloudflare-record-comment` tags every managed record; ownership itself is
still the TXT, not the comment.

## The cluster runs its own resolver

A second CoreDNS lives in the `dns` namespace as a DaemonSet on **hostPort 53**,
udp and tcp, exactly like Traefik: every node answers on `10.82.50.10x:53`, so
LAN hosts can use it directly. In-cluster it is also a Service pinned to
`10.96.0.53`.

**hostPort, not hostNetwork.** The pod keeps its own network namespace, so
`dnsPolicy: None` with `nameserver 127.0.0.1` makes it resolve through itself and
never through the node — the loop the campus resolver would otherwise close. A
`hostNetwork` pod would instead bind `0.0.0.0:53` in the host namespace and
contend with Talos's own host DNS resolver.

The namespace is labelled `pod-security.kubernetes.io/enforce: privileged` for
the same reason Traefik's is: baseline forbids hostPort. A DaemonSet does not
surge on rollout, so unlike Traefik it needs no `maxSurge` correction.

### Adding a record by hand

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

### DNS4EU first, Quad9 behind it

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

### Campus taxes the first TLS connection, and CoreDNS caps DoH at 2s

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

### Internal-only `gewis.nl` names do not resolve through it

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

## The kube-system Corefile is ours now

`flux/config/coredns/corefile.yaml` is a verbatim copy of the Corefile Talos
generates, with the `forward` replaced by two stanzas:

```
forward . 10.96.0.53 /etc/resolv.conf {
   policy sequential
   next SERVFAIL REFUSED
}
forward . /etc/resolv.conf
```

The resolver first, campus DNS behind it. Sequential means the resolver is used
whenever it is healthy; `max_fails` defaults to 2 and retires an upstream once it
has failed *more* than that, after which *forward* moves down the list.

**Two different failures need two different mechanisms, and this is easy to get
wrong.** Walking the upstream list only happens on a network error. A resolver
that is up but answering SERVFAIL — its own upstream filtered, say — is a
*successful* exchange, so the SERVFAIL is written straight to the client and
`/etc/resolv.conf` is never tried. `next` is what covers that: on a matching
RCODE it hands the query to the following plugin, which must itself be a
*forward*, hence the second stanza.

| Failure | Covered by | Measured |
| --- | --- | --- |
| DaemonSet gone (dead socket) | in-list `/etc/resolv.conf` | 3 queries at ~2s, then ~20ms, none lost |
| resolver up, answering SERVFAIL | `next` → second stanza | `NOERROR` via campus DNS in 14ms |

Without the second stanza the SERVFAIL case returns `rc2` to every pod. Verified
both ways against the real Corefile.

`next` is the right tool here and `failover` is not: `failover` retries within the
same list, and when *every* upstream returns the RCODE its loop resets its counter
at the end of the list and spins until the 5s deadline. `next` is a single hop.
Adding it costs nothing on the dead-socket path — latency is identical to the
single-stanza version.

Owning that ConfigMap is safe because **Talos applies bootstrap manifests exactly
once**. Its `ManifestApplyController` keeps an inventory and skips any object that
already exists, so it will not fight Flux — and Flux applies server-side with
`ForceOwnership`, so it takes the `Corefile` field from Talos's field manager
without a conflict. On a cold rebuild Talos creates the default first and Flux
overwrites it seconds later.

Two consequences follow from that, and both bite:

- **Deleting the file deletes cluster DNS config.** The `config` layer prunes,
  and Talos will not put the ConfigMap back.
- **A Talos upgrade will not update it.** If Sidero changes the default Corefile,
  diff against `k8stemplates.CoreDNSConfigMap` and re-vendor by hand.

CoreDNS's `reload` plugin picks the change up within ~30s, so nothing has to be
restarted.

## OpenBao

Three-replica Raft, sealed with a static key from a SealedSecret and reached at
`https://openbao.cbc.gewis.nl:8443`.

It self-initialises. Auto-unseal cannot unseal a barrier that was never
initialised, and a StatefulSet will not start pod 1 until pod 0 is `Ready`, so an
uninitialised OpenBao deadlocks at pod 0. The `initialize` stanza breaks that on
first boot, and it only runs against **empty storage** — a partially-initialised
PVC has to be deleted for it to re-run.

Self-init requests take flat values only; a nested map is rejected as `invalid
request`, and a failed request is fatal to the process. The root token is created
and immediately revoked, so the stanza must also provision a way in — here the
Kubernetes auth method bound to the `openbao-admin` ServiceAccount, which avoids
storing an admin password anywhere:

```sh
bao write auth/kubernetes/login role=admin \
  jwt="$(kubectl -n openbao create token openbao-admin)"
```

`.envrc` exports that token as `TF_VAR_bao_jwt` for the `openbao-config` root,
failing quietly when the cluster is unreachable.

`disable_mlock` is not a valid OpenBao 2.x option; it was removed and is only
warned about, not rejected.

## Reading the failure, not the symptom

Several of these surfaced far from their cause. Worth remembering:

- Longhorn pods crash-looping on one node — the node was memory-starved by
  hypervisor ballooning.
- external-dns "up to date" while doing nothing — the zone was filtered out.
- HTTPRoute with an empty `status` — the Gateway controller never started, so
  nothing had accepted the route.
- "Could not connect" in ~15 ms is a TCP reset: the packet arrived and was
  refused. A firewall drop times out instead.
