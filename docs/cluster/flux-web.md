# Flux Web UI

The operator serves a status UI on `:9080`: every Flux object's readiness, the
event stream, and a graph from sources through Kustomizations and HelmReleases to
the workloads they deploy. It is published at `flux.cbc.gewis.nl`, and it is
**read-only**.

## Read-only by RBAC, not by UI setting

The UI never acts with its own permissions. `helm-release.yaml` sets
`authentication.type: Anonymous` with the username `flux-web-viewer`, so every
request is made by impersonating that user, and
`flux/apps/flux-web/rbac.yaml` binds it to a ClusterRole with only `get`, `list`
and `watch` on the Flux APIs, workloads, pods, services, namespaces and events.
Any action the UI offers is refused by the API server.

The chart's own roles are switched off (`web.rbac.createRoles: false`) because
its `flux-web-user` grants `get` on `*/*`, secrets included. ConfigMaps and
Secrets are deliberately absent from `flux-web-viewer`.

## Access goes through authentik

The UI has no login of its own in anonymous mode, so it sits behind the authentik
proxy outpost exactly like [Hubble](../observability/hubble.md):
`flux/apps/flux-web/httproute.yaml` holds the `ExternalAuth` route and the
`ReferenceGrant`, and the `flux` proxy client in
`terraform/authentik-config/proxy.tf` registers the provider with the `cbc`
outpost. Like Hubble, any authentik user who can log in can open it.

## Only the gateway may reach it

The `FluxInstance` sets `networkPolicy: true`, which isolates `flux-system` from
other namespaces. The chart's NetworkPolicy would open `:9080` to every pod in
the cluster, skipping authentik entirely, so it is disabled
(`web.networkPolicy.create: false`). Instead a `CiliumNetworkPolicy` admits only
the `ingress` entity — the identity Cilium gives traffic from its Gateway API
Envoy. A plain NetworkPolicy cannot express that: a `namespaceSelector` matches
pods, and the gateway's traffic belongs to no namespace.

To look at it without the gateway:

```sh
kubectl -n flux-system port-forward svc/flux-operator 9080:9080
```
