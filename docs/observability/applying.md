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

## When Grafana's database is newer than the state

Every org-scoped resource here is addressed by an org ID that Grafana assigns, and
orgs live only in Grafana's own database — which is the `grafana` database in the
Postgres cluster, so it is replicated and backed up with everything else rather
than sitting on one volume. Lose it anyway, or point the root at a different
Grafana, and the state still names orgs that no longer exist. The failure does not
say so:

```
Error: error reading datasource with ID`8:mimir-cbc`: [GET /datasources/uid/{uid}][403]
  {"message":"You'll need additional permissions to perform this action.
   Permissions needed: datasources:read"}
```

A 403 rather than a 404, because the provider asks for the org with
`X-Grafana-Org-Id: 8` and Grafana refuses a context the caller is not a member
of — which is every org that does not exist. Refresh fails for all forty
resources, so the plan aborts before showing a single change. Confirm with
`curl -u admin:… /api/orgs`: if the answer is only `Main Org.`, this is what
happened.

There is nothing to repair in Grafana. Drop the stale objects from the state and
let the next apply rebuild them:

```sh
tofu state rm grafana_organization.tenant \
  grafana_data_source.loki grafana_data_source.mimir grafana_data_source.tempo \
  grafana_data_source.loki_live grafana_dashboard.cbc \
  grafana_dashboard.cbc_pinned_datasource grafana_dashboard.cbc_sealed_secrets
tofu apply
```

Orgs come back with new IDs, which nothing outside this root depends on:
`org_mapping` keys off org *names*, so users land in the right place on their next
login. `-refresh=false` is not a shortcut here — it leaves the dead IDs in state
and the apply silently does nothing.
