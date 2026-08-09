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
superuser, so `enableSuperuserAccess` stays `false`. `provisioner` is the role
`initdb` creates, elevated by the one managed-role entry on the `Cluster`:

```yaml
bootstrap:
  initdb:
    database: provisioner
    owner: provisioner

managed:
  roles:
    - name: provisioner
      createdb: true
      createrole: true
```

**No `passwordSecret`, deliberately.** The CRD is explicit that a null
`passwordSecret` means "the password will be ignored", so the entry adds the two
attributes and leaves the credential alone — and the credential is the one
CloudNativePG generated at bootstrap, sitting in `postgres-app`. Tofu reads it
out of the cluster with the `kubernetes` provider, the same shape as
`grafana-config` reading `grafana-auth`.

Nobody types this password, and it never appears in git. That is the point, and
the two alternatives are worse:

- **Minting it in tofu** puts the credential in the root that then wants to log
  in with it. The password cannot reach Postgres until External Secrets and
  CloudNativePG have both acted, which no single apply can wait for, so every
  fresh cluster needs a `-target` incantation to break the cycle.
- **A superuser** would be a standing field on a shared manifest bound for
  production, and needlessly broad, to save two lines.

The cost is one vestigial `provisioner` database that nothing uses — `initdb`
insists on creating one.

From Postgres 16 onward the creator of a role holds `ADMIN OPTION` on it, so
`provisioner` can hand each database to the role it just made.

## Roles that predate this root

`Database` and `DatabaseRole` both default to `retain`, so anything those CRDs
created outlives them. Either adopt it:

```sh
tofu import 'postgresql_role.app["authentik"]' authentik
tofu import 'postgresql_database.app["authentik"]' authentik
```

or delete the `Cluster` and let it rebootstrap empty, which is the cheaper move
while the databases hold nothing worth keeping.

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
