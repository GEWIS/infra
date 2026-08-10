# Ingress arrives on the host network, not a LoadBalancer

There is no LoadBalancer and no VIP. A `CiliumLoadBalancerIPPool` plus a static
route was the original plan; it was dropped because Cilium's Gateway API
supports **host network mode** (`gatewayAPI.hostNetwork.enabled`), which exposes
the per-node Envoy listener on every node directly. The router simply dst-nats
`:8443` to a node's `:443`. No LB-IPAM, no BGP, nothing to announce.

On the MikroTik side, **`To Ports` must be set to 443**. Leave it empty and
`dst-nat` preserves the original port, forwarding to `:8443` where nothing is
listening — the connection is refused in milliseconds, which looks exactly like
a firewall block but is not one.

**In host network mode the `Gateway` listener port *is* the host port.** There is
no mapping, so `spec.listeners[].port` is 443 rather than some higher number the
chart then republishes. Envoy holds no Linux capabilities by default and cannot
bind below 1024, so that costs two Helm values:

```hcl
envoy = {
  enabled = true
  securityContext = {
    capabilities = {
      keepCapNetBindService = true
      envoy                 = ["NET_ADMIN", "SYS_ADMIN", "NET_BIND_SERVICE"]
    }
  }
}
```

`keepCapNetBindService` is what survives `cilium-envoy-starter` dropping
capabilities around the Envoy process; granting the capability to the container
alone is not enough. These live under `envoy.*` because the standalone
`cilium-envoy` DaemonSet is what runs — in embedded mode the capability goes on
`securityContext.capabilities.ciliumAgent` instead.

What host network mode does **not** cost is a Pod Security exemption. Envoy runs
in `kube-system`, which Talos leaves unenforced, so no namespace needs a
`pod-security.kubernetes.io/enforce: privileged` label for ingress — unlike the
`hostPort` workloads described in [the resolver](../cluster/resolver.md).

Two restrictions come with it, neither of which applies here: host network mode
and the LoadBalancer Service mode are mutually exclusive, and `TCPRoute`/
`UDPRoute` traffic bypasses Envoy and would land on a `NodePort` with a random
port instead of the listener's.

## Replacing what listens on 443

A rollout that changes *what* binds `:443` on the nodes cannot overlap. Anything
holding the port — a `hostPort` DaemonSet, or an older Envoy — must be gone
before a 443 listener exists, or the new bind fails with `EADDRINUSE` and the
`Gateway` never programs. Enable `gatewayAPI` first, while no `Gateway` object
exists and therefore nothing is bound, and only then apply the `Gateway`
together with the removal of whatever it replaces.
