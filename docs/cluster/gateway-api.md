# Gateway API is an add-on, and its version must match Cilium

Gateway API is **not** part of Kubernetes and nothing installs it by default —
not Talos, and not Cilium unless `gatewayAPI.enabled` is set. It is pulled from
upstream by the `crds` layer via a `GitRepository` pinned to a tag, so Renovate
keeps it current; vendoring the YAML would work too but Renovate cannot bump a
static blob.

**Pin the version to what the controller wants, not to whatever is newest-looking.**
Cilium 1.20 requires Gateway API **v1.6.1 at a minimum**, and a controller whose
informers watch a kind at a version the cluster does not serve fails with *"the
server could not find the requested resource"* — indistinguishable from the CRDs
being absent. The provider then never syncs, so:

```
GatewayClass  Accepted=Unknown  "Waiting for controller"
Gateway       Programmed=Unknown
HTTPRoute     status: <empty>
```

and external-dns, which reads targets from an HTTPRoute's `status.parents`,
silently emits nothing.

Use the **experimental** channel, for three reasons:

- `TLSRoute` in the v1.6 *standard* channel no longer ships `v1alpha2`. Install
  that one over an existing `TLSRoute` and the apiserver cannot read the records
  out of etcd — the objects simply disappear. Upstream flags this as an upgrade
  action for Cilium 1.20.
- The `ExternalAuth` HTTPRoute filter field exists only in experimental. See
  [Routing](routing.md).
- `ListenerSet`, `TCPRoute` and `UDPRoute` are separate CRDs, and Cilium
  disables the corresponding feature for each one that is missing.

The channel is a strict superset of standard, so nothing is lost by using it.
