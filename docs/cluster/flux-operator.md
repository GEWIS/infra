# Flux is installed by the Flux Operator

Flux itself is one object: the `FluxInstance` in
`flux/clusters/gewis-prod/flux-system/flux-instance.yaml`. The
[Flux Operator](https://fluxoperator.dev) turns it into the controllers, the
`flux-system` `GitRepository` (`GEWIS/infra`, `main`) and the root `flux-system`
`Kustomization` (`flux/clusters/gewis-prod`), which applies the
[layers](layers.md).

| File in `flux/clusters/gewis-prod/flux-system/` | Holds |
| --- | --- |
| `flux-instance.yaml` | Flux version (pinned), components, sync target |
| `helm-repo.yaml` | The operator's OCI chart repository |
| `helm-release.yaml` | The operator itself, pinned, plus its Web UI values |

Only `source-controller`, `kustomize-controller` and `helm-controller` run.
`notification-controller` is left out because nothing here uses an `Alert`,
`Provider` or `Receiver`; add it to `components` when something does.

## Upgrades

Both are pinned and bumped by Renovate, so every upgrade is a commit:

- **Flux**: `distribution.version` in `flux-instance.yaml`, matched by a regex
  manager in `renovate.json` against `fluxcd/flux2` releases. The operator could
  follow a range like `2.8.x` on its own, but then upgrades would leave no trace
  in Git.
- **The operator**: an ordinary pinned HelmRelease, like every other chart.

## Bootstrap: tofu starts it, Flux owns it

`terraform/20_talos-bootstrap/flux.tf` uses the upstream
`controlplaneio-fluxcd/flux-operator-bootstrap` module. It runs a one-shot Job
that installs the operator chart and applies the `FluxInstance`, both read from
the files above so bootstrap and steady state never disagree. Both are
*create-if-missing*: once Flux has adopted them the Job leaves them alone, so a
later `tofu apply` never fights Flux. Changing either file makes the next
`20_talos-bootstrap` apply re-run the Job, which then finds everything adopted and
does nothing.

The module depends on `helm_release.cilium`. The Job gets a single attempt
(`backoffLimit: 0`), and on a fresh cluster it would otherwise start while
Cilium is still rolling out, with no pod network, and fail the apply. Waiting
for the Cilium release guarantees the pod network, not that CoreDNS is ready or
that the first TLS connection to ghcr.io gets through; if the Job still fails,
`debug_on_failure = true` on the module relays its log into the tofu output.

The module needs the Helm provider 3.x, which is why `20_talos-bootstrap` pins
`~> 3.1`.

## Migrating the running cluster

The cluster was first set up with `flux bootstrap`. The operator adopts that
install in place, without downtime: it strips the `kustomize.toolkit.fluxcd.io`
ownership labels from the controllers and marks them
`kustomize.toolkit.fluxcd.io/prune: Disabled`, so removing the old `gotk-*.yaml`
from Git cannot garbage-collect running controllers. Order matters:

1. `tofu apply` in `terraform/20_talos-bootstrap` — installs the operator and the
   `FluxInstance`; wait for `kubectl -n flux-system get fluxinstance flux` to
   report `Ready`.
2. Only then push the commit that removes `flux-system/gotk-*.yaml` and
   `flux-system.yaml`. Pushed first, the tree would contain a `FluxInstance`
   whose CRD does not exist yet, and the root `Kustomization` would fail its
   dry-run.
3. `flux trace kustomization flux-system` now answers *object not managed by
   Flux*: the operator owns it, not a Kustomization. The three controllers carry
   `app.kubernetes.io/managed-by: flux-operator`. `notification-controller` is
   still running until the push, because the operator never adopted it: it keeps
   its `kustomize.toolkit.fluxcd.io/name: flux-system` label and sits in that
   Kustomization's inventory, so the first reconcile after the push prunes it
   along with its CRDs.
