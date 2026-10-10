# The MariaDB cluster as deployed

One `MariaDB` named `mariadb` in the `mariadb` namespace: three pods with
asynchronous replication, one primary and two replicas, each on its own
`longhorn-single` volume of 50 GiB. The operator, mariadb-operator, lives in
`controllers` (`flux/20_controllers/mariadb-operator/`), so its CRDs exist before
`services` declares the cluster in `flux/40_services/mariadb/`.

Applications share this one cluster and are separated by user and database, the
same as on [Postgres](postgres.md).

The image is pinned to MariaDB **12.3**, the operator's default image. Replication
relies on the `master_ssl_verify_server_cert` server option (see [TLS](#tls));
11.8 refuses it as an unknown variable.

## Replication and failover

| Setting | Value | Effect |
| --- | --- | --- |
| `replication.primary.autoFailover` | `true` | the operator promotes a replica when the primary goes down |
| `replication.semiSyncWaitPoint` | `AfterSync` | a commit becomes visible only after a replica has acknowledged it |
| `semiSyncAckTimeout` | `10s` (default) | without an acknowledgement for 10s the primary continues asynchronously |
| `affinity.antiAffinityEnabled` | `true` | one pod per node |

The timeout is a known gap: with both replicas gone, writes continue unprotected
rather than stop, and a failover after such a period can lose the writes of that
period.

Updates use `ReplicasFirstPrimaryLast`: the replicas restart one at a time, then
the primary restarts **in place**, so writes stop for one pod restart. Before a
planned update, move the primary by hand and let the update restart it as a
replica:

```sh
kubectl -n mariadb patch mariadb mariadb --type merge \
  -p '{"spec":{"replication":{"primary":{"podIndex":1}}}}'
```

## Reached on a LoadBalancer IP

The operator's `mariadb-primary` Service is a `LoadBalancer` on
**`10.82.50.13:3306`**, announced over L2 by Cilium like
[Traefik](../cluster/traefik.md). The operator points its selector at the current
primary pod and moves it on failover. `mariadb.cbc.gewis.nl` resolves to that
address through the [cluster resolver](../cluster/resolver.md); every client,
inside the cluster or not, connects by that name.

## TLS

The server presents a Let's Encrypt certificate for `mariadb.cbc.gewis.nl`, issued
by cert-manager (`certificate.yaml`) and mounted from the `mariadb-tls` Secret.
Clients verify it against their system CA store; nobody needs a CA file.

| Piece | Where |
| --- | --- |
| `ssl_cert`, `ssl_key` | `myCnf` in `mariadb.yaml`, pointing at `/etc/mariadb-tls` |
| Operator-managed TLS | `tls.enabled: false` |
| TLS required | per user: `REQUIRE SSL` on every application user, set by tofu |
| Replication | `master_ssl_verify_server_cert = 0` in `myCnf` |
| Physical backups, replica rebuilds | `--disable-ssl-verify-server-cert` in the `PhysicalBackup` `args` |

Everything the operator runs connects by the pod's internal name, which the
certificate does not carry:

| Connection | Server certificate check |
| --- | --- |
| Replication | off: encrypted, but the replica does not authenticate the primary; Cilium's WireGuard also encrypts the hop between nodes |
| `mariadb-backup` in `PhysicalBackup` Jobs | off, through `args` |
| `mariadb` client (`FLUSH SSL`, point-in-time replay) | passes through the client library's fingerprint check, derived from the password of a `mysql_native_password` user |
| Operator, agent, exporter | no TLS |

Application users get `REQUIRE SSL`; the server-wide `require_secure_transport`
stays off, so the connections without TLS above keep working.

**A new connection path from the operator needs testing against this setup.**
`mariadb-backup` without the flag fails with *"SSL certificate validation
failure"*, and so does a replica without `master_ssl_verify_server_cert = 0`.

### Renewal needs a reload

MariaDB reads its certificate at startup. cert-manager renews the Secret 30 days
before expiry and the mounted files follow, but the server keeps serving the old
certificate until it runs `FLUSH SSL`. The `tls-reload` CronJob
(`tls-reload.yaml`) runs that on every pod daily at 04:30, as root, using the
operator-generated `mariadb-root` Secret.

## Adding a database is one map entry

`terraform/40_databases` owns MariaDB users and databases the same way it owns
Postgres roles:

```hcl
mariadb_databases = {
  wiki = { namespace = "wiki" }
}
```

That mints a password, creates the user with `REQUIRE SSL`, the database and a
grant of the database-level privileges, writes the credential to OpenBao at
`mariadb/<namespace>/<database>`, and creates the OpenBao role `mariadb-<namespace>`
that namespace's `ExternalSecret` logs in with. The credential's `host` is
`mariadb.cbc.gewis.nl`.

## Tofu connects as `provisioner`

`spec.username: provisioner` with a generated `passwordSecretKeyRef` makes the
operator create the user and its password Secret `mariadb-provisioner`, which tofu
reads with the `kubernetes` provider. A `Grant` in `mariadb.yaml` gives it
`CREATE USER` and every database-level privilege on `*.*` with `GRANT OPTION`,
because MariaDB lets a user grant only privileges it holds itself. It is not a
superuser, but it can read every application's data.

`spec.database: provisioner` creates an empty `provisioner` database that nothing
uses.

## Backups

See [Backups](backups.md#mariadb-physical-backups-and-binlog-archiving).

## Metrics

`metrics.enabled: true` makes the operator run mysqld-exporter as a Deployment
and publish a `ServiceMonitor`. The operator deploys the exporter only when the
`ServiceMonitor` CRD exists, which is why `controllers` installs the
`prometheus-operator-crds` chart beside it. Alloy reads `ServiceMonitor`s in the
`mariadb` namespace with `prometheus.operator.servicemonitors`. The alerts are in
[Alerting](../observability/alerting.md#the-mariadb-rules).
