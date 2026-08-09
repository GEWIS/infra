# cluster

What runs *inside* the Talos cluster, and how Flux orders it. The cluster itself
— VMs, machine config, CNI — is [`docs/talos.md`](../talos/index.md).

Everything here is reconciled by Flux from `flux/`, with one `Kustomization` per
layer in `flux/clusters/gewis-prod/`.
