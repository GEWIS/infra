# Which mount, and why not `secret`

This root owns its own `seaweedfs` kv-v2 mount. `terraform/40_openbao-config` owns
`secret`; two roots declaring the same `vault_mount` is a state fight, and a
dedicated mount makes the policy paths
(`seaweedfs/data/<namespace>/<bucket>`) fall out without prefix gymnastics.

Layout under the mount:

| Object | Name |
| --- | --- |
| Mount | `seaweedfs` (kv-v2) |
| KV entry | `<namespace>/<bucket>`, e.g. `observability/loki` |
| Policy | `seaweedfs-<namespace>-<bucket>`, e.g. `seaweedfs-observability-loki` |
| Kubernetes auth role | `seaweedfs-<namespace>`, e.g. `seaweedfs-observability` |

Each policy grants `read` on `seaweedfs/data/<ns>/<bucket>` and
`seaweedfs/metadata/<ns>/<bucket>` and nothing else. The role carries every
policy for its namespace, so a pod in `observability` can read all three
observability entries and no entry belonging to another namespace.

The Kubernetes auth backend itself is **not** declared here. The OpenBao Helm
release bootstraps `auth/kubernetes`, the `admin` policy and the `admin` role
through its `initialize` stanza; this root only adds roles underneath it. So
`flux/openbao` must be reconciled before the first apply.
