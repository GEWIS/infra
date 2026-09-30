# cluster

What runs *inside* the Talos cluster, and how Flux orders it. The cluster itself
— VMs, machine config, CNI — is [`docs/talos.md`](../talos/index.md).

Everything here is reconciled by Flux from `flux/`, with one `Kustomization` per
layer in `flux/clusters/gewis-prod/`. Flux itself is installed and upgraded by the
[Flux Operator](flux-operator.md), which also serves a read-only
[status UI](flux-web.md).
