# Networking is single-stack IPv4, and that is permanent

```
podSubnets     10.244.0.0/16
serviceSubnets 10.96.0.0/12
```

Pod and service CIDRs, the primary family, `dnsDomain` and `cni.name` are all
effectively immutable — changing them is a rolling rebuild of every node, so they
are decided here and not later.

**Dual-stack is not free while the nodes are v4-only.** With a ULA prefix in both
subnet lists, Talos hands out v6 pod CIDRs and kube-apiserver assigns a v6
ClusterIP to every Service, but the nodes have no IPv6 address at all — they sit on
`10.82.50.0/24`. Cilium says so on startup:

```
IPv6 is enabled, but Cilium cannot find the IPv6 address for this node.
This may cause connectivity disruption for Endpoints that attempt to communicate using IPv6
```

Endpoints get v6 addresses, `kube-dns` advertises `fd00:cbc:1::a` next to
`10.96.0.10`, and the first workload whose resolver prefers the v6 answer fails with
`EHOSTUNREACH` on a ClusterIP nothing can route. cert-manager's DNS-01 self-check
found that edge and stalled every certificate behind it. Half a stack is worse than
none: the addresses exist, so clients try them.

Adding v6 back is deliberate work rather than a flag — a routable prefix on the
nodes first, then these CIDRs at a rebuild, then Cilium's `ipv6.enabled`.

IPv6-only was rejected outright: `ghcr.io` has no AAAA on its registry endpoint and
`registry.gitlab.com` none at all, so an IPv6-only cluster cannot even pull the
images `fleet-infra` uses without NAT64 + DNS64 — two single points of failure, for
no external IPv6 anyway while the uplink is v4-only.

`machine.kubelet.nodeIP.validSubnets` pins the node InternalIP to `10.82.50.0/24`,
so kubelet does not pick an address at random from a multi-homed node.

The cluster shares `10.82.50.0/24` with everything else deliberately: a firewall
VLAN would sit at the wrong layer. Cilium masquerades all pod egress to the node
address, so a VLAN ACL could only ever express per-node rules, never
per-workload — `CiliumNetworkPolicy` egress does that properly, keyed on pod
identity, and keeps Garage on the same L2 with no router in the S3 path.
