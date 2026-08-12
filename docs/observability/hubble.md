# Hubble

Every Cilium agent serves its own flow API on `:4244`; `hubble.enabled` is on by
default. The Cilium values in `terraform/talos-bootstrap/main.tf` add the two
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

Hubble UI has no login of its own, so the route in `flux/config/gateway/hubble.yaml`
puts an `ExternalAuth` filter in front of it — the GEP-1494 filter Cilium 1.20
added, described in [Routing](../cluster/routing.md). Envoy calls the auth service
over `ext_authz` before it forwards anything, and a request without a session gets
that service's redirect instead of the app.

The auth service is an authentik **proxy provider** in `forward_single` mode, served
by a dedicated outpost that authentik deploys itself through the
`Local Kubernetes Cluster` service connection — `terraform/authentik-config/proxy.tf`
declares the provider, the application and the outpost, and authentik creates the
`ak-outpost-cbc` Deployment and Service in its own namespace.

Two details make the route work:

- **The first rule is not protected.** `/outpost.goauthentik.io/` goes straight to
  the outpost, because that is where the browser lands after authenticating and it
  cannot be behind the check it is trying to satisfy.
- **The filter needs `cookie` in and `set-cookie` out.** `allowedHeaders` is what
  Envoy forwards to the auth service, `allowedResponseHeaders` is what it copies
  onward, and a session cannot survive without both. The
  `x-authentik-{username,groups,email}` headers ride along for anything that wants
  to read the identity.

A `ReferenceGrant` in the `authentik` namespace permits both references, since the
route lives in `kube-system` with Hubble.

`hubble.metrics.enabled` is unset, so the four Hubble dashboards in the Cilium
chart are not imported — see [Dashboards](dashboards.md). They cost more than a
flag: their panels read `source` and `destination` labels that exist only when
every metric carries `sourceContext`/`destinationContext` options, the namespace
filters need a `labelsContext` on top, and the resulting series count scales with
namespace or pod pairs against a single-replica Mimir. The live flow view answers
the same questions without storing anything.
