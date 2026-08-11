# Gateway API is an add-on, and its version must match Cilium

Gateway API is **not** part of Kubernetes and nothing installs it by default —
not Talos, and not Cilium unless `gatewayAPI.enabled` is set. It comes from
`terraform/talos-bootstrap`, which applies the upstream `experimental-install.yaml`
for a pinned release before the Cilium chart; a Renovate `customManager` bumps
`gateway_api_version` against GitHub releases.

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

## Cilium reads the CRDs at startup, so tofu owns them

Cilium is the CNI: nothing else runs until it does, which puts it ahead of Flux and
therefore ahead of anything Flux could apply. That ordering is why the CRDs cannot
live in a Flux layer. Cilium disables Gateway API support for every one of its CRDs
missing at startup, and the chart's `gatewayAPI.gatewayClass.create: auto` decides
at *template* time by looking for the `GatewayClass` CRD — so CRDs that arrive two
minutes later leave neither a controller nor a `GatewayClass`, with
`enable-gateway-api=true` sitting in the ConfigMap the whole time. The `Gateway`
then waits on a class that does not exist:

```
$ kubectl get gatewayclass
(nothing)
$ kubectl -n gateway get gateway
Accepted=Unknown  reason=Pending  msg="Waiting for controller"
```

Nothing binds `:443` and every external request is refused at the TCP level, which
reads as "the gateway was never installed" rather than as an ordering problem.

`kubectl_manifest` with `server_side_apply` does the applying, because these are
13 CRDs of 24 000 lines — client-side apply stores the whole object in an
annotation and blows the size limit. `gatewayClass.create` stays `auto`: forcing it
`true` renders a `GatewayClass` unconditionally, which is a hard Helm failure on an
unknown kind if the CRDs ever are missing.
