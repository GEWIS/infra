# The Postgres cluster as deployed

One CloudNativePG `Cluster` named `postgres` in the `postgres` namespace, three
instances on the `longhorn-single` storage class. The operator lives in
`controllers`, so its CRDs exist before any layer that declares a `Cluster`.

Applications do not get a cluster each. A three-instance cluster per app would
multiply pods and volumes for no isolation this cluster needs, so consumers share
one and are separated by role and database instead.

## Adding a database is one map entry

`terraform/postgres-databases` owns every credential *and* the DDL. One entry is
the whole change:

```hcl
databases = {
  authentik = { namespace = "authentik" }
}
```

That mints a password, writes it to OpenBao at `postgres/<namespace>/<database>`,
and issues the `CREATE ROLE` and `CREATE DATABASE` itself through the
`cyrilgdn/postgresql` provider. Nothing per-application exists in the `postgres`
namespace; the consuming namespace reads its own credential with an
`ExternalSecret`, and that is the only Kubernetes object involved.

## How tofu reaches a cluster with no public address

A `NodePort` Service publishes the primary on **30432**, selecting
`cnpg.io/instanceRole: primary`. Cilium forwards from any node to wherever that
pod currently is, and CNPG relabels on failover, so the address survives a
primary change. `hostPort` — how Traefik and the resolver are exposed — is not an
option here: the `Cluster` CRD has no field for it, and it would bind on all
three nodes with only one of them writable.

The endpoint is `kube.gewis.nl:30432`, which round-robins the node addresses.
`postgres.cbc.gewis.nl` is the same thing through the cluster resolver, which
rewrites it onto `kube.gewis.nl`; use it from inside the cluster, and the node
name from a workstation, which resolves through campus DNS and has never heard
of the resolver's private names.

## Tofu connects as `provisioner`, not as a superuser

`CREATE ROLE` and `CREATE DATABASE` need `CREATEROLE` and `CREATEDB` — not
superuser, so `enableSuperuserAccess` stays `false`. There is exactly one managed
role on the `Cluster`:

```yaml
managed:
  roles:
    - name: provisioner
      login: true
      createdb: true
      createrole: true
      passwordSecret:
        name: provisioner-role
```

Its password takes the same route as everyone else's — tofu writes it to OpenBao,
an `ExternalSecret` in the `postgres` namespace turns it into the
`kubernetes.io/basic-auth` Secret CNPG expects. From Postgres 16 onward the
creator of a role holds `ADMIN OPTION` on it, so `provisioner` can hand each
database to the role it just made.

A superuser would have been a standing field on the shared cluster manifest,
carried into production, to save two lines. Not worth it.

## The first apply is two-phase

`provisioner` cannot exist until its password does, and its password comes from
the root that wants to log in as it. On a fresh cluster, break the cycle
explicitly:

```sh
tofu apply -target=vault_kv_secret_v2.provisioner \
           -target=vault_policy.provisioner_read \
           -target=vault_kubernetes_auth_backend_role.cluster
# wait for External Secrets to sync and CNPG to create the role
tofu apply
```

Only the first apply against empty OpenBao needs this. Afterwards the role exists
and a plain `tofu apply` is enough.

Databases that predate this root — anything the `Database` and `DatabaseRole`
CRDs created — are adopted rather than recreated, because both reclaim policies
default to `retain` and the objects outlive the CRs:

```sh
tofu import 'postgresql_role.app["authentik"]' authentik
tofu import 'postgresql_database.app["authentik"]' authentik
```

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
