# Networking is dual-stack, and that is permanent

```
podSubnets     10.244.0.0/16   fd00:cbc:0::/56
serviceSubnets 10.96.0.0/12    fd00:cbc:1::/108
```

IPv4 is primary (first entry wins), IPv6 is ULA. Pod and service CIDRs, the
primary family, `dnsDomain` and `cni.name` are all effectively immutable —
changing them is a rolling rebuild of every node, so they are decided here and
not later. Dual-stack now costs nothing (IPv4 still does all egress, no NAT64)
and means a real IPv6 prefix, when one ever arrives, is added to interfaces
without a rebuild.

IPv6-only was rejected: `ghcr.io` has no AAAA on its registry endpoint and
`registry.gitlab.com` none at all, so an IPv6-only cluster cannot even pull the
images `fleet-infra` uses without standing up NAT64 + DNS64 — two single points
of failure, for no external IPv6 anyway while the uplink is v4-only.

`machine.kubelet.nodeIP.validSubnets` pins the node InternalIP to the v4 subnet,
so kubelet does not pick an address family at random on a dual-stack node.

The cluster shares `10.82.50.0/24` with everything else deliberately: a firewall
VLAN would sit at the wrong layer. Cilium masquerades all pod egress to the node
address, so a VLAN ACL could only ever express per-node rules, never
per-workload — `CiliumNetworkPolicy` egress does that properly, keyed on pod
identity, and keeps Garage on the same L2 with no router in the S3 path.
