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

Both are reached through the CLI, which port-forwards:

```sh
cilium hubble ui                      # opens the UI in a browser
cilium hubble port-forward &          # then: hubble observe --follow
```

## No route, and no metrics

Hubble UI authenticates nobody, so it has no `HTTPRoute` and no DNS name.
Exposing it takes an `ExternalAuth` filter in front of it — see
[Routing](../cluster/routing.md). A port-forward requires cluster credentials,
which is the boundary that stands in for that filter.

`hubble.metrics.enabled` is unset, so the four Hubble dashboards in the Cilium
chart are not imported — see [Dashboards](dashboards.md). They cost more than a
flag: their panels read `source` and `destination` labels that exist only when
every metric carries `sourceContext`/`destinationContext` options, the namespace
filters need a `labelsContext` on top, and the resulting series count scales with
namespace or pod pairs against a single-replica Mimir. The live flow view answers
the same questions without storing anything.
