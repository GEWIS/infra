# Ingress arrives on hostPort, not a LoadBalancer

There is no LoadBalancer and no VIP. A `CiliumLoadBalancerIPPool` plus a static
route was the original plan; it was dropped because Traefik runs as a
**DaemonSet binding hostPort 80 and 443** on every node, and the router simply
dst-nats `:8443` to a node's `:443`. No LB-IPAM, no BGP, nothing to announce.

On the MikroTik side, **`To Ports` must be set to 443**. Leave it empty and
`dst-nat` preserves the original port, forwarding to `:8443` where nothing is
listening — the connection is refused in milliseconds, which looks exactly like
a firewall block but is not one.

`hostPort` costs two things:

- **Pod Security Admission baseline forbids hostPort.** Talos enforces baseline
  on every namespace except `kube-system`, so `traefik` must be labelled
  `pod-security.kubernetes.io/enforce: privileged`.
- **The chart's default rollout deadlocks.** `maxSurge: 1, maxUnavailable: 0`
  wants the replacement pod `Ready` before the old one goes, but it cannot bind a
  port the old pod still holds. Invert to `maxUnavailable: 1, maxSurge: 0`.
