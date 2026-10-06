# Ingress arrives on a LoadBalancer IP announced over L2

Public HTTPS reaches the cluster on one address, **`10.82.50.200`**: the
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

The pool is `10.82.50.200`–`229`, outside the router's DHCP range so a lease can
never collide with an announced IP. The pool and the `CiliumL2AnnouncementPolicy`
live in `terraform/20_talos-bootstrap/load-balancer.tf`, next to Cilium.

## The router forwards `:8443` to `:443`

router02 dst-nats public `:8443` to `10.82.50.200:443`, which is why every public
URL carries `:8443`.

On the MikroTik side, **`To Ports` must be set to 443**. Leave it empty and
`dst-nat` preserves the original port, forwarding to `:8443` where nothing is
listening — the connection is refused in milliseconds, which looks exactly like
a firewall block but is not one.
