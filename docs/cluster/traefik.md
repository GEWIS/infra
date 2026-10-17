# Ingress is Traefik

Traefik is the cluster's front door for HTTPS. It is a Flux controller in
`flux/20_controllers/traefik/`, and every public hostname is an `IngressRoute`
served by it.

## Reached on a LoadBalancer IP

Traefik's Service is a `LoadBalancer` pinned to **`10.82.50.10`** with the
`lbipam.cilium.io/ips` annotation. Cilium hands it out and answers ARP for it:

| Piece | Where |
| --- | --- |
| `l2announcements.enabled`, raised `k8sClientRateLimit` | Cilium values in `terraform/20_talos-bootstrap/main.tf` |
| `CiliumLoadBalancerIPPool` `default`, `10.82.50.10`–`50` | `terraform/20_talos-bootstrap/load-balancer.tf` |
| `CiliumL2AnnouncementPolicy` `default`, LoadBalancer IPs on every node | same file |

The pool and policy live in OpenTofu next to Cilium rather than in Flux. Flux
installs the Traefik chart and waits for it, and a `LoadBalancer` Service is not
ready until it has an address; a pool in a later Flux layer would never arrive,
because that layer waits for this one. The pool stays clear of router02, the
other low addresses and the old cluster's MetalLB pool (`.150`–`.199`), which stays in use until
that cluster is gone.

Every announced IP holds a Kubernetes lease that its node renews every few
seconds, which is what the raised client rate limit is for. Which node holds it,
and how the router reaches it, is in [Ingress](../talos/ingress.md).

`rollOutCiliumPods` and `operator.rollOutPods` are on, so a change to the Cilium
values restarts the agents and the operator. Cilium reads `cilium-config` only at
startup; without them a values change such as enabling L2 announcements lands in
the ConfigMap and does nothing until the pods are restarted by hand.

Traefik is a DaemonSet with `externalTrafficPolicy: Local`, so the client address
survives into Traefik. With `Local`, Cilium only announces from a node that runs a
Traefik pod; the DaemonSet puts one on every node, so any node can take over the
IP when another dies.

router02 forwards public `:443` to this address — see
[Ingress](../talos/ingress.md#router02-forwards-public-443-here).

## Client addresses

| Setting on `websecure` | Trusts | Why |
| --- | --- | --- |
| `forwardedHeaders.trustedIPs` | `131.155.10.134`, `.135` (TU/e WAF), `145.116.44.49`, `145.116.47.68` (Geproxy) | proxies that terminate TLS in front of router02; their `X-Forwarded-For` is kept |

A connection from anywhere else is taken as the client itself, and any
`X-Forwarded-For` it sends is replaced.

`transport.respondingTimeouts.readTimeout: 0` lifts the default 60 s cap on
reading a request, which would otherwise cut off large uploads.

### `X-Real-Ip` comes from our own plugin

Traefik sets `X-Real-Ip` to the connecting address, and keeps whatever a trusted
proxy sends. The TU/e WAF appends the client to an `X-Forwarded-For` the client
may already have filled in, and passes a client's own `X-Real-Ip` through, so
neither header is trustworthy as received. The published plugins that rewrite it
pick the leftmost `X-Forwarded-For` entry, which the client controls.

The `real-ip` plugin in `flux/20_controllers/traefik/real-ip/` always overwrites
`X-Real-Ip`. If the connecting address is not a trusted proxy, that address is
the client. Otherwise it walks `X-Forwarded-For` from the right and takes the
first address that is not a trusted proxy; an unparsable entry, or a chain of
only trusted proxies, falls back to the connecting address. Its trusted list is
the Middleware `traefik/real-ip` in `flux/30_config/traefik/`, and must match
`forwardedHeaders.trustedIPs`. `websecure` applies it to every route through
`http.middlewares`, so no route has to name it; if it fails to load, every
route on `websecure` fails with it. On a cold build that is the state between the
`controllers` and `config` layers, since the Middleware arrives with `config`.
Nothing `config` needs goes through Traefik. The `openbao` layer depends only on
`controllers`, so `openbao.gewis.nl` can be refused until `config` is applied;
everything that uses OpenBao in the cluster talks to `openbao-active` directly.

Traefik runs it as a local plugin: a kustomization in that directory turns the
source into the ConfigMap `traefik-real-ip`, which the HelmRelease mounts under
`/plugins-local/src/github.com/gewis/traefik-real-ip`. Traefik loads plugins only
at startup, so a change to the source needs
`kubectl -n traefik rollout restart ds/traefik`. Run the tests in that directory
with `go test ./...`, and under Traefik's interpreter with `yaegi test .` from a
`GOPATH` layout.

## Error pages

Every route on `websecure` that answers 401, 403 or any `5xx` (but not 404,
see below) gets a
GEWIS-styled page in place of the backend's: a full-bleed `#D40000` background
(the `$gewis-red` from [gewisweb](https://github.com/GEWIS/gewisweb)) with the
white GEWIS logo (`static.gewis.nl/logo/SVG/Full_Logo_White.svg`, its own black
background square stripped out), the original status code and its reason phrase
(`HTTP 502 — Bad Gateway`) as the heading, and the line asking the visitor to
email `cbc@gewis.nl` if the error looks wrong. The status code of the response
is not rewritten; Traefik swaps the body only.

The Middleware `traefik/error-pages` lives in
`flux/20_controllers/traefik/error-pages/middleware.yaml` and the `websecure` entry point lists
it after `traefik-real-ip` in the Traefik HelmRelease
(`flux/20_controllers/traefik/helm-release.yaml`) — it is an
entry-point middleware, so no route has to name it. It ships in the same
directory as the error-pages workload instead of the `config` layer: the
HelmRelease references it, and a Middleware that is missing when a Traefik
pod starts makes every route on `websecure` answer plain `404 page not
found`. The Middleware CR cannot apply before the chart has installed its
CRDs, and the kustomizer retries applying it (`retryInterval` on the layer),
so a pod booting in that gap serves the broken state until it lands; Traefik
then picks the middleware up through the provider watch and rebuilds the
routers, no restart.

The errors middleware reacts to a status alone and cannot tell an error
Traefik produced from one the backend returned. The only one that matters for
that is 404, and 404 is not listed — applications keep ownership of it, and
every 404 Traefik produces is covered by the fallback router below. The whole
`5xx` range is listed, so an application answering its own 503 (a maintenance
page) is restyled too, accepted knowingly: a Traefik-generated 503 cannot be
told apart, and a dead backend winning the page is the point — it is what
`judge.gehack.nl` shows while DOMjudge's domserver is unready. Nor are the
other `4xx` codes listed: replacement bodies would deny API clients
machine-readable errors such as Keycloak's token-endpoint responses. Note that
401 and 403 are listed, so a keyed-on 401 from an auth backend replaces the
machine-readable body it would otherwise emit.

The page is served by nginx: Deployment and Service `error-pages` in the
`traefik` namespace from `flux/20_controllers/traefik/error-pages/`, two
unprivileged read-only-root replicas of `nginx:1.28-alpine` behind
`error-pages:8080`. Its ConfigMap (`traefik-error-pages-nginx`) holds the
`nginx.conf` and one page template: the errors middleware asks for
`/{status}.html`, nginx captures the status from the request path, maps it to a
reason phrase (`default: "Error"` for the long tail), and SSI-echoes code and
phrase into the template. A change to the ConfigMap needs
`kubectl -n traefik rollout restart deploy/error-pages`, since nginx reads its
configuration only at startup. The logo is inlined as a data URI because the browser
fetches everything but the swapped body from the host that failed, not from
this server, so a plain `logo.svg` reference would never reach it. The
The Middleware and the Service both live in `traefik`, so `allowCrossNamespace`
staying off changes nothing.

A host that no `IngressRoute` matches never reaches a backend: Traefik's
internal fallback router answers plain `404 page not found` and, unlike every
real router, takes no part in entry-point middlewares — so the Middleware
alone cannot restyle it. The `IngressRoute error-pages-fallback` in
`error-pages/catch-all.yaml` closes that hole: with `priority: 1` it can only
match requests no other router wanted, and it sends them to the error-page
nginx, whose `location /` serves the styled 404 itself through
`error_page 404 /404.html` — no errors middleware involved, which is exactly
why the 404 covers everything Traefik has to refuse without ever replacing a
404 an application produced. The
unknown-SNI-terminates-on-the-default-`*.cbc.gewis.nl` part is unchanged.

## Routes are IngressRoutes

Every published service has an `IngressRoute` on the `websecure` entry point,
next to the workload it serves: `flux/30_openbao/`, `flux/40_services/s3/`,
`flux/50_apps/authentik/`, `flux/50_apps/observability/grafana/`,
`flux/50_apps/hubble/`, `flux/50_apps/flux-web/`, `flux/50_apps/longhorn/`,
`flux/50_apps/netbird/` and `flux/50_apps/keycloak/`,
each in an `ingressroute.yaml`. Routes to hosts outside the cluster live in
`flux/50_apps/external-proxy/`, see [External proxy](external-proxy.md); S3 is the
exception, see [S3](s3.md). `web`
(`:80`) only redirects to HTTPS. The `traefik` IngressClass is the cluster
default, so a plain `Ingress` also lands here.

TLS comes from the default TLS store: `wildcard-cbc-gewis-nl-tls` in the
`traefik` namespace, issued by its own [`Certificate`](certificates.md). A route
needs only `tls: {}`.

Each route carries `external-dns.alpha.kubernetes.io/target:
router02.net.gewis.nl`, the CNAME target for its hostname — see [DNS](dns.md).

`allowCrossNamespace` stays off: a route may only point at Services and
Middlewares in its own namespace, so an app namespace cannot publish another
namespace's Service.

`allowExternalNameServices` stays off as well, so a route cannot publish an
arbitrary host by name. Hosts outside the cluster are reached through a
selectorless Service with a hand-written `EndpointSlice` for their LAN address —
see [External proxy](external-proxy.md).

## Keycloak-protected apps use the `traefik-oidc-auth` plugin

The HelmRelease loads `traefik-oidc-auth` `v0.18.0` from the plugin catalog.
Apps that log in through Keycloak use it in a Middleware, with their own
client and an `oidc-secret` per namespace, see
[Forward auth](../keycloak/forward-auth.md). Traefik downloads plugins at
startup, so a version change restarts every pod in the DaemonSet.

## Authentication is ForwardAuth to the authentik outpost

A protected route uses a `forwardAuth` Middleware in its own namespace, pointing
at the `cbc` proxy outpost by its cluster address:

```yaml
forwardAuth:
  address: http://ak-outpost-cbc.authentik.svc.cluster.local:9000/outpost.goauthentik.io/auth/traefik
  trustForwardHeader: true
  authResponseHeaders: [X-authentik-username, X-authentik-groups, X-authentik-email]
```

The login callback, `/outpost.goauthentik.io/`, has to reach the outpost on every
protected host. One `IngressRoute` in the `authentik` namespace matches that path
on any host, with `priority: 10000` so it beats every app's `Host(...)` rule,
which Traefik would otherwise rank higher by rule length. A new protected app
needs only the Middleware on its route.

If the outpost is unreachable, the `forwardAuth` request fails and Traefik
refuses the request rather than serving it.

## The outpost publishes nothing itself

authentik's outpost controller would create its own routing objects for the
protected hosts: an `Ingress`, an `HTTPRoute` and a Traefik `Middleware`. The
`cbc` outpost disables all three with `kubernetes_disabled_components` in
`terraform/50_authentik-config/proxy.tf`, so it runs only its Deployment and
Service. The `Ingress` in particular would land on the default class and make
Traefik log errors about its TLS secret, which does not exist; the
`outpost-callback` route already covers those paths.

Disabling a component stops authentik from reconciling it; an object it already
created stays until it is deleted by hand.

The provider sends `config` as a whole, replacing what authentik stored, so
that block carries the outpost's complete configuration, not just the change.
