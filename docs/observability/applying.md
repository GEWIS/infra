# Applying

Flux brings up the workloads. The Grafana side is one apply once Grafana answers:

```sh
cd terraform/grafana-config
tofu init
tofu apply
```

The root has no credential of its own. It reads the `grafana-auth` Secret out of
the `observability` namespace with the `kubernetes` provider and authenticates as
that admin user, so the password exists in exactly one place — the SealedSecret
in git. This couples the root to the cluster, which costs nothing it was not
already paying: Grafana has to be up and reachable for an apply to do anything at
all. The kubeconfig defaults to the repository's `.kube/config`, which `.envrc`
mints.
