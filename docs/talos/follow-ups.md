# Known follow-ups

The cluster is bootstrapped and healthy: three control-plane nodes `Ready`,
etcd/apid/kubelet green, and `talosctl health` passes. Cilium, Flux, Longhorn,
cert-manager, external-dns and OpenBao are installed and running, and
`https://openbao.cbc.gewis.nl:8443` serves a trusted certificate. What remains:

- **Ingress depends on a single node.** The router dst-nats to `10.82.50.101`
  only, so that node is a single point of failure even though every node listens
  on 443.
- **The imported VDI is labelled `talos-1.13.8-nocloud-disk`.** Purely cosmetic;
  rename it in XO if the generic label bothers you.
