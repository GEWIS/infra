# Other prerequisites

- **Three DHCP reservations** on the `10.82.50.0/24` server, pinning the pinned
  MACs to fixed addresses. The nodes run DHCP; the reservation is what makes the
  address stable and collision-safe. tofu sets the MACs; the reservation keys off
  them, so the two must match exactly.

  | Node | MAC | Address |
  | --- | --- | --- |
  | talos-01 | `00:16:3e:5e:b8:01` | 10.82.50.101 |
  | talos-02 | `00:16:3e:5e:b8:02` | 10.82.50.102 |
  | talos-03 | `00:16:3e:5e:b8:03` | 10.82.50.103 |

- **`kube.gewis.nl`** with an A record to each of the three addresses. It is the
  API endpoint, baked into every kubeconfig and every certificate SAN, so it is
  effectively permanent — a DNS name rather than an IP precisely so a node can be
  replaced without reissuing PKI. There is deliberately no Talos VIP: it is
  IPv4-only and depends on etcd, unusable exactly when the API is in trouble.

- The `10.82.50.0/24` subnet is already a NetBird routing-peer resource, so the
  nodes are reachable over the mesh the moment they boot, with no NetBird on them.
