# Reading the failure, not the symptom

Several of these surfaced far from their cause. Worth remembering:

- Longhorn pods crash-looping on one node — the node was memory-starved by
  hypervisor ballooning.
- external-dns "up to date" while doing nothing — the zone was filtered out.
- A Cilium value present in `cilium-config` and ignored — the agents read that
  ConfigMap only at startup. `rollOutCiliumPods` restarts them on every
  values change; see [Ingress](traefik.md#reached-on-a-loadbalancer-ip).
- "Could not connect" in ~15 ms is a TCP reset: the packet arrived and was
  refused. A firewall drop times out instead.
