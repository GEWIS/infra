# The Postgres cluster as deployed

One CloudNativePG `Cluster` named `postgres` in the `postgres` namespace, three
instances on the `longhorn-single` storage class. The operator lives in
`controllers`, so its CRDs exist before any layer that declares a `Cluster`.

Applications do not get a cluster each. A three-instance cluster per app would
multiply pods and volumes for no isolation this cluster needs, so consumers share
one and are separated by role and database instead.

Rolling updates promote an already-updated replica before touching the old
primary (`primaryUpdateMethod: switchover`), so a restart costs a few seconds of
refused writes and dropped connections rather than the primary's whole restart.
The primary moves to another node each time; the `postgres-primary` NodePort
and `postgres-rw` follow it.

## Adding a database is one map entry

`terraform/40_postgres-databases` owns every credential *and* the DDL. One entry is
the whole change:

```hcl
databases = {
  authentik = { namespace = "authentik" }
  grafana   = { namespace = "observability" }
  netbird   = { namespace = "netbird" }
  loom      = { namespace = "loom" }
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
primary change. `hostPort` — how the resolver is exposed — is not an
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
      login: true
      createdb: true
      createrole: true
```

**No `passwordSecret`, deliberately.** The CRD is explicit that a null
`passwordSecret` means "the password will be ignored", so the entry adds the
attributes and leaves the credential alone — and the credential is the one
CloudNativePG generated at bootstrap, sitting in `postgres-app`. Tofu reads it
out of the cluster with the `kubernetes` provider, the same shape as
`60_grafana-config` reading `grafana-auth`.

**`login: true` is not redundant, even though `initdb` already created the role
with it.** A managed role is reconciled to its declared state, and `Login` is a
plain `bool` with `omitempty` documented as defaulting to `false` — so omitting
it makes CloudNativePG issue `ALTER ROLE provisioner NOLOGIN` and every
connection afterwards fails with *"role is not permitted to log in"*. The
neighbouring fields are safe to omit: `inherit` is a `*bool` defaulting true,
`connectionLimit` defaults to `-1`, and `superuser`, `replication` and
`bypassrls` all default false, which is what we want.

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

or delete the `Cluster` and let it rebootstrap empty — but only after deleting
its WAL archive under `s3://postgres/postgres/` as well. A freshly initialised
cluster with the same name finds a non-empty archive, and Barman refuses to
archive into it. The same holds for a cluster restored from a backup: it needs
its own `serverName` in the plugin parameters, or it archives on top of the
timeline it was restored from.

## Sizing

Each instance gets a 50 GiB volume, one replica on each node's 300 GiB Longhorn
disk, so the databases moving over from the old cluster fit with room to spare.
`longhorn-single` allows volume expansion, so raising `storage.size` grows the
volumes in place without a rebuild.

`max_wal_size` stays at Postgres's 1 GB default. Cap it only on a volume of a
few GiB, where a full write-ahead log would fill the volume and stop the
database.

## A killed pod can deadlock the next one's migrations

Applications that migrate on startup — authentik does — take a Postgres advisory
lock first, so two replicas cannot migrate at once. That lock belongs to the
*session*, and a session outlives the pod that opened it.

When a pod is killed abruptly, the TCP connection is never torn down. Postgres
keeps the backend, the transaction, and the advisory lock, and by default will
not notice the peer is gone for hours, because `tcp_keepalives_idle` defaults to
`0` (meaning the system default, typically two hours). Every replacement pod then
queues behind a process that no longer exists:

```
 pid  | granted |        state
------+---------+---------------------
 1900 | t       | idle in transaction     <- pod is long gone
 2045 | f       | active                  <- waiting forever
```

The application looks like it is hanging on migrations. It is not: it is waiting
on a corpse, and no restart can fix it, because each restart adds another corpse.
`pg_terminate_backend` on the holder releases it instantly.

Four parameters stop it happening again:

| Parameter | Value | Why |
| --- | --- | --- |
| `tcp_keepalives_idle` | `60` | start probing a silent peer after a minute |
| `tcp_keepalives_interval` | `10` | retry every ten seconds |
| `tcp_keepalives_count` | `3` | give up after three, so a dead peer is reaped in ~90s |
| `idle_in_transaction_session_timeout` | `60000` | backstop for a live client that opens a transaction and stops |

Migrations hold *active* transactions, not idle ones, so the timeout does not
interrupt them.

## Database volumes opt out of the recurring jobs

Every `RecurringJob` in `flux/30_config/longhorn/recurring-jobs.yaml` lists `default`
in its groups, and Longhorn adds `recurring-job-group.longhorn.io/default:
enabled` to any volume that carries no recurring-job label at all. Database
volumes would therefore collect hourly snapshots and weekly backups that
duplicate the [Barman backups](backups.md).

Removing the label does not work — `labelRecurringJobDefault` re-adds it on every
reconcile as long as no *other* job or group label is present. The volume has to
belong to something else instead, which the storage class arranges at creation:

```yaml
parameters:
  recurringJobSelector: '[{"name":"none","isGroup":true}]'
```

No `RecurringJob` names the `none` group, so nothing fires, and the presence of
the label is what keeps `default` off.
