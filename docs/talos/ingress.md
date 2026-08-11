# Ingress arrives on the host network, not a LoadBalancer

There is no LoadBalancer, no VIP and no LB-IPAM pool. Cilium's Gateway API runs in
**host network mode** (`gatewayAPI.hostNetwork.enabled`), which exposes the
per-node Envoy listener directly on every node, and the router dst-nats `:8443` to
a node's `:443`. Nothing is announced, so there is no BGP and no static route to
an address the cluster owns.

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

Envoy owns `:443` on every node exclusively. A second process binding it — a
`hostPort` DaemonSet, or a second Envoy during a rollout — fails with
`EADDRINUSE`, and the `Gateway` stays un-`Programmed` until the port is free.
