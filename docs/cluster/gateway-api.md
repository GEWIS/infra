# Gateway API is an add-on, and its version must match Traefik

Gateway API is **not** part of Kubernetes and nothing installs it by default —
not Talos, not the Traefik chart (which ships only `traefik.io` CRDs), and not
Cilium unless `gatewayAPI.enabled` is set. It is pulled from upstream by the
`crds` layer via a `GitRepository` pinned to a tag, so Renovate keeps it current;
vendoring the YAML would work too but Renovate cannot bump a static blob.

**Pin the version to what the controller wants, not to whatever is newest-looking.**
Traefik 3.7.5 watches `TLSRoute` and `BackendTLSPolicy` at `gateway.networking.k8s.io/v1`.
Gateway API v1.2.1 serves those at `v1alpha2`/`v1alpha3`, so its informers fail
with *"the server could not find the requested resource"* — indistinguishable
from the CRDs being absent. The provider then never syncs, so:

```
GatewayClass  Accepted=Unknown  "Waiting for controller"
Gateway       Programmed=Unknown
HTTPRoute     status: <empty>
```

and external-dns, which reads targets from an HTTPRoute's `status.parents`,
silently emits nothing. v1.6.1 serves both at `v1` and fixes it.

Use the **experimental** channel. Traefik watches those kinds regardless of the
chart's `experimentalChannel: false`, so the CRDs must exist either way; the
channel is a strict superset of standard.

Traefik does not rebuild its Gateway API informers after startup — installing the
CRDs under a running Traefik changes nothing until the pods restart.
