# Reading the failure, not the symptom

Several of these surfaced far from their cause. Worth remembering:

- Longhorn pods crash-looping on one node — the node was memory-starved by
  hypervisor ballooning.
- external-dns "up to date" while doing nothing — the zone was filtered out.
- HTTPRoute with an empty `status` — the Gateway controller never started, so
  nothing had accepted the route.
- "Could not connect" in ~15 ms is a TCP reset: the packet arrived and was
  refused. A firewall drop times out instead.
