# Ingress arrives on a LoadBalancer IP announced over L2

Public HTTPS reaches the cluster on one address, **`10.82.50.10`**: the
`LoadBalancer` IP of [Traefik](../cluster/traefik.md). No node owns it in its
machine config. Cilium hands it out from a `CiliumLoadBalancerIPPool` and answers
ARP for it from whichever node holds the Kubernetes lease
`cilium-l2announce-traefik-traefik` in `kube-system`:

```sh
kubectl -n kube-system get lease cilium-l2announce-traefik-traefik
```

When that node goes away its lease expires, another node takes it and starts
answering ARP, so no node is a single point of failure. Nothing is routed, so
there is no BGP and no static route on the router — the address is just another
host on `10.82.50.0/24`.

The pool is `10.82.50.10`–`50`, clear of router02 and the other low addresses on
the subnet. The pool and the `CiliumL2AnnouncementPolicy` live in
`terraform/20_talos-bootstrap/load-balancer.tf`, next to Cilium.

| Address | Service |
| --- | --- |
| `10.82.50.10` | Traefik |
| `10.82.50.11` | the cluster [resolver](../cluster/resolver.md), `dns-lan` |
| `10.82.50.12` | the [Postgres](../databases/postgres.md) primary, `postgres-lan` |
| `10.82.50.13` | the [MariaDB](../databases/mariadb.md) primary, `mariadb-primary` |
| `10.82.50.14` | [NetBird](../cluster/netbird.md) STUN, `netbird-stun` (UDP 3478) |

## Public `:443` arrives through the previous cluster

router02 forwards public `:443` to the previous cluster's Traefik, which still
serves the apps that have not moved yet. That Traefik passes this cluster's
hostnames through untouched, by SNI, to `10.82.50.10:443`: an `IngressRouteTCP`
`new-cluster-passthrough` with `tls.passthrough: true` in its `netbird`
namespace, pointing at a selectorless Service and an EndpointSlice
`new-cluster-traefik`. Its `ServersTransportTCP` `new-cluster-proxy-protocol`
prepends a PROXY protocol v2 header, so this Traefik sees the real client address
rather than the previous cluster's node — see
[Client addresses](../cluster/traefik.md#client-addresses).

| Hostname | Reaches router02 |
| --- | --- |
| `openbao`, `authentik`, `flux`, `hubble`, `kite`, `longhorn`, `nb`, `print` `.gewis.nl` | directly (CNAME `router02.net.gewis.nl`) |
| `grafana.gewis.nl` | through the TU/e WAF (CNAME `waf.gewis.nl`), which terminates TLS with its own certificate and connects on to router02 with the same SNI |

A new public hostname on this cluster needs a `HostSNI` there as well, or the
previous Traefik answers it itself. If the previous Traefik still has an HTTP
route of its own for that hostname, that route wins over the passthrough, even
with an explicit `priority`; the old route has to be removed first. The
passthrough's endpoint carries `conditions.ready: true`; without it Traefik treats
the Service as empty and drops the connection mid-handshake.

A browser that already holds an HTTP/2 connection to that Traefik for another
`*.gewis.nl` host reuses it for these names, so the request never shows its SNI
and gets the previous Traefik's `404 page not found` until the browser opens a
fresh connection. Non-browser clients are not affected.

This section goes away when router02's `:443` points at `10.82.50.10`. The older
forward of public `:8443` to `10.82.50.10:443` is no longer used by any URL.
