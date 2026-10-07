# Flux Web UI

The operator serves a status UI on `:9080`: every Flux object's readiness, the
event stream, and a graph from sources through Kustomizations and HelmReleases to
the workloads they deploy. It is published at `flux.cbc.gewis.nl`, and it is
**read-only**.

## Read-only by RBAC, not by UI setting

The UI never acts with its own permissions. `helm-release.yaml` sets
`authentication.type: Anonymous` with the username `flux-web-viewer`, so every
request is made by impersonating that user, and
`flux/50_apps/flux-web/rbac.yaml` binds it to a ClusterRole with only `get`, `list`
and `watch` on the Flux APIs, workloads, pods, services, namespaces and events.
Any action the UI offers is refused by the API server.

The chart's own roles are switched off (`web.rbac.createRoles: false`) because
its `flux-web-user` grants `get` on `*/*`, secrets included. ConfigMaps and
Secrets are deliberately absent from `flux-web-viewer`.

## Access goes through authentik

The UI has no login of its own in anonymous mode, so it sits behind the authentik
proxy outpost exactly like [Hubble](../observability/hubble.md):
`flux/50_apps/flux-web/ingressroute.yaml` holds the route and its `forwardAuth`
Middleware (see [Ingress](traefik.md#authentication-is-forwardauth-to-the-authentik-outpost)),
and the `flux` proxy client in `terraform/50_authentik-config/proxy.tf` registers
the provider with the `cbc` outpost. Like Hubble, any authentik user who can log
in can open it.

## Only Traefik may reach it

The `FluxInstance` sets `networkPolicy: true`, which isolates `flux-system` from
other namespaces. The chart's NetworkPolicy would open `:9080` to every pod in
the cluster, skipping authentik entirely, so it is disabled
(`web.networkPolicy.create: false`). Instead the `CiliumNetworkPolicy`
`flux-web-from-traefik`, in the same file, admits on `:9080` only pods labelled
`app.kubernetes.io/name: traefik` in the `traefik` namespace. Matching on both
keeps a pod that merely borrows the label elsewhere out.

To look at it without Traefik:

```sh
kubectl -n flux-system port-forward svc/flux-operator 9080:9080
```
