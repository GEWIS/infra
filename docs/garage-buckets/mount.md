# Which mount, and why not `secret`

This root owns its own `garage` kv-v2 mount. `terraform/openbao-config` owns
`secret`; two roots declaring the same `vault_mount` is a state fight, and a
dedicated mount makes the policy paths (`garage/data/<ns>/<bucket>`) fall out
without prefix gymnastics.

The Kubernetes auth backend itself is **not** declared here. The OpenBao Helm
release bootstraps `auth/kubernetes`, the `admin` policy and the `admin` role
through its `initialize` stanza; this root only adds roles underneath it. So
`flux/openbao` must be reconciled before the first apply.
