# Hubble

Every Cilium agent serves its own flow API on `:4244`; `hubble.enabled` is on by
default. The Cilium values in `terraform/20_talos-bootstrap/main.tf` add the two
components that are not:

```hcl
hubble = {
  relay = { enabled = true }
  ui    = { enabled = true }
}
```

`relay` is a single gRPC endpoint that fans out to all three agents, so one query
covers the cluster rather than one node. `ui` is the flow map and service
dependency graph on top of relay.

The UI is published at `hubble.cbc.gewis.nl`, and `hubble observe` runs over a
port-forward:

```sh
cilium hubble port-forward &          # then: hubble observe --follow
```

## The UI authenticates through authentik, not itself

Hubble UI has no login of its own, so its `IngressRoute` in
`flux/apps/hubble/ingressroute.yaml` runs every request through a `forwardAuth`
Middleware in `kube-system`, described in
[Ingress](../cluster/traefik.md#authentication-is-forwardauth-to-the-authentik-outpost).
Traefik asks the auth service before it forwards anything, and a request without a
session gets that service's redirect instead of the app.

The route lives in Flux rather than next to Hubble in OpenTofu because the
`IngressRoute` and `Middleware` CRDs arrive with Traefik in the `controllers`
layer — see [Layers](../cluster/layers.md).

The auth service is an authentik **proxy provider** in `forward_single` mode, served
by a dedicated outpost that authentik deploys itself through the
`Local Kubernetes Cluster` service connection — `terraform/50_authentik-config/proxy.tf`
declares the provider, the application and the outpost, and authentik creates the
`ak-outpost-cbc` Deployment and Service in its own namespace.

Two details make it work:

- **The callback is not protected.** `/outpost.goauthentik.io/` goes straight to
  the outpost through the `outpost-callback` route in the `authentik` namespace,
  because that is where the browser lands after authenticating and it cannot be
  behind the check it is trying to satisfy.
- **The Middleware names the outpost by URL, not by Service reference.** A route
  may only reference objects in its own namespace, so the auth address is the
  outpost's cluster DNS name. `X-authentik-{username,groups,email}` ride along
  for anything that wants to read the identity.

`hubble.metrics.enabled` is unset, so the four Hubble dashboards in the Cilium
chart are not imported — see [Dashboards](dashboards.md). They cost more than a
flag: their panels read `source` and `destination` labels that exist only when
every metric carries `sourceContext`/`destinationContext` options, the namespace
filters need a `labelsContext` on top, and the resulting series count scales with
namespace or pod pairs against a single-replica Mimir. The live flow view answers
the same questions without storing anything.
