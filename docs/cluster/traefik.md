# Ingress is Traefik

Traefik is the cluster's front door for HTTPS. It is a Flux controller in
`flux/controllers/traefik/`, and every public hostname is an `IngressRoute`
served by it.

## Reached on a LoadBalancer IP

Traefik's Service is a `LoadBalancer` pinned to **`10.82.50.200`** with the
`lbipam.cilium.io/ips` annotation. Cilium hands it out and answers ARP for it:

| Piece | Where |
| --- | --- |
| `l2announcements.enabled`, raised `k8sClientRateLimit` | Cilium values in `terraform/20_talos-bootstrap/main.tf` |
| `CiliumLoadBalancerIPPool` `default`, `10.82.50.200`–`229` | `terraform/20_talos-bootstrap/load-balancer.tf` |
| `CiliumL2AnnouncementPolicy` `default`, LoadBalancer IPs on every node | same file |

The pool and policy live in OpenTofu next to Cilium rather than in Flux. Flux
installs the Traefik chart and waits for it, and a `LoadBalancer` Service is not
ready until it has an address; a pool in a later Flux layer would never arrive,
because that layer waits for this one. The pool sits outside the router's DHCP
range and next to the old cluster's MetalLB pool (`.150`–`.199`), which stays in
use until that cluster is gone.

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

router02 forwards public `:8443` to `10.82.50.200:443`, which is why every public
URL in the OpenTofu roots and Grafana carries `:8443`.

## Routes are IngressRoutes

Every published service has an `IngressRoute` on the `websecure` entry point,
next to the workload it serves: `flux/openbao/`, `flux/apps/authentik/`,
`flux/apps/observability/grafana/`, `flux/apps/hubble/` and
`flux/apps/flux-web/`, each in an `ingressroute.yaml`. `web` (`:80`) only
redirects to HTTPS. The `traefik` IngressClass is the cluster default, so a plain
`Ingress` also lands here.

TLS comes from the default TLS store: `wildcard-cbc-gewis-nl-tls` in the
`traefik` namespace, issued by its own [`Certificate`](certificates.md). A route
needs only `tls: {}`.

Each route carries `external-dns.alpha.kubernetes.io/target:
router02.net.gewis.nl`, the CNAME target for its hostname — see [DNS](dns.md).

`allowCrossNamespace` stays off: a route may only point at Services and
Middlewares in its own namespace, so an app namespace cannot publish another
namespace's Service.

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

## The outpost's own Ingress logs TLS errors

authentik's outpost controller creates an `Ingress` of its own, `ak-outpost-cbc`,
carrying only the `/outpost.goauthentik.io` paths for the protected hosts and a
TLS secret, `authentik-outpost-tls`, that does not exist. With no class set it
falls to the default class, so Traefik serves it and logs an error about the
missing secret. It is harmless: those paths already reach the outpost through
`outpost-callback`, and the wildcard from the default store covers the hosts.
