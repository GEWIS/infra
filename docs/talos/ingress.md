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
| `10.82.50.16` | Traefik's [internal entrypoint](../cluster/traefik.md#internal-only-routes-use-the-internal-entrypoint), `traefik-internal`, for LAN-only routes |

## router02 forwards public `:443` here

router02 dst-nats public `:443` to `10.82.50.10:443`. The source address is kept,
and `externalTrafficPolicy: Local` keeps it into Traefik.

| Hostname | Reaches router02 |
| --- | --- |
| most names, e.g. `openbao`, `authentik`, `nb`, `docker`, `phpmyadmin` `.gewis.nl` | directly (CNAME `router02.net.gewis.nl`) |
| `gewis.nl`, `grafana`, `wiki`, `docker-registry` and others | through the TU/e WAF (`waf.gewis.nl`), which terminates TLS with its own certificate and connects on to router02 with the same SNI |

The older forward of public `:8443` to `10.82.50.10:443` is no longer used by any
URL.
