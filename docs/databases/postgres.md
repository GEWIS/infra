# The Postgres cluster as deployed

One CloudNativePG `Cluster` named `postgres` in the `postgres` namespace, three
instances on the `longhorn-single` storage class. The operator lives in
`controllers`, so its CRDs exist before any layer that declares a `Cluster`.

Applications do not get a cluster each. A three-instance cluster per app would
multiply pods and volumes for no isolation this cluster needs, so consumers share
one and are separated by role and database instead.

## Adding a database is two files and an apply

The role password is minted by `terraform/postgres-databases` — one entry in the
`databases` map — and lands in OpenBao at `postgres/<namespace>/<database>`:

```hcl
databases = {
  authentik = { namespace = "authentik" }
}
```

From there it is read twice, by two `ExternalSecret`s in two namespaces:

| Namespace | Secret | Consumed by |
| --- | --- | --- |
| `postgres` | `<app>-role`, `kubernetes.io/basic-auth` | `DatabaseRole.spec.passwordSecret` |
| the app's | whatever shape the app wants | the app |

One credential, two readers, no copy of the password anywhere else. This is the
same route the Garage bucket credentials take, and it exists for the same reason:
a `SecretStore` is namespaced, so each side authenticates as itself.

The role and the database are declared with CRDs rather than fields on the
`Cluster`:

```yaml
kind: DatabaseRole            kind: Database
spec:                         spec:
  cluster: {name: postgres}     cluster: {name: postgres}
  name: authentik               name: authentik
  login: true                   owner: authentik
  passwordSecret:
    name: authentik-role
```

`Cluster.spec.managed.roles` would work equally well and is the older way, but it
puts every consumer inside one shared object — adding an app would mean editing
the cluster every other app depends on. With the CRDs, adding a consumer only
ever adds files.

**Apply the tofu root before pushing the manifests.** The `ExternalSecret` reads
a path that does not exist until then, so `DatabaseRole` has no password to use
and `services` sits un-`Ready` for its whole timeout. It heals as soon as the KV
entry appears, but it looks broken until it does.

## Two settings the disk forces

Each node has a 9 GiB Longhorn disk with roughly 7 GiB already scheduled, because
every other volume here is three-replica. That leaves about 2 GiB per node, and
three replica-1 Postgres instances place one volume on each.

- **`storage.size: 1Gi`.** Two would consume the entire remainder.
- **`max_wal_size: 256MB`.** Postgres defaults to 1 GB. On a 1 GiB volume that is
  a volume that fills with write-ahead log and stops the database — the default
  is only safe on a disk sized for it.

The real headroom is elsewhere: Loki, Mimir, Tempo and Grafana sit on
three-replica Longhorn while their data lives in Garage. Moving those four to
`longhorn-single` frees roughly 4.7 GiB per node.

## Database volumes opt out of the recurring jobs

Every `RecurringJob` in `flux/config/longhorn/recurring-jobs.yaml` lists `default`
in its groups, and Longhorn adds `recurring-job-group.longhorn.io/default:
enabled` to any volume that carries no recurring-job label at all. Database
volumes would therefore collect hourly snapshots and weekly backups that
duplicate the logical dumps.

Removing the label does not work — `labelRecurringJobDefault` re-adds it on every
reconcile as long as no *other* job or group label is present. The volume has to
belong to something else instead, which the storage class arranges at creation:

```yaml
parameters:
  recurringJobSelector: '[{"name":"none","isGroup":true}]'
```

No `RecurringJob` names the `none` group, so nothing fires, and the presence of
the label is what keeps `default` off.
