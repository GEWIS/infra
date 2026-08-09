# databases

How HA Postgres and MariaDB are placed on this cluster, why the redundancy lives
where it does, and how they are backed up. Nothing here is deployed yet —
`flux/apps` is empty — this is the design the build follows.

## Replicate at the database layer, never at both

A database that replicates itself must sit on single-replica storage. The failure
mode to avoid is stacking the database's own replication on top of Longhorn's, so
the same bytes are mirrored twice by two layers that do not know about each other.

Count the copies for a three-instance database:

| Layout | DB instances | Longhorn replicas/vol | Total copies | Real HA |
| --- | --- | --- | --- | --- |
| single instance, normal Longhorn | 1 | 3 | 3× | storage-only, reattach with downtime |
| three instances, replica-1 Longhorn | 3 | 1 | 3× | yes, database-layer failover |
| three instances, normal Longhorn | 3 | 3 | 9× | yes, wastefully |

The single-instance and three-instance-replica-1 layouts store the data the same
3×. The difference is only how those three copies are spent: three block-mirrors
of one process, or three independent database replicas. For equal disk the second
buys real HA — automatic failover instead of a volume reattach — so it is the
choice. The 9× layout is the anti-pattern and is rejected outright.

The rule that falls out: **database volumes go on a `numberOfReplicas: 1` storage
class, and the database owns its own redundancy.** Losing a node takes one
instance with it; the operator rebuilds a fresh replica from the survivors.

## The stack per engine

**Postgres — CloudNativePG.** Three instances, one primary and two replicas, each
its own PVC on the replica-1 class. Streaming replication, automatic failover in
seconds, a lost replica rebuilt from its peers. The operator makes the
three-instance layout nearly free to run.

**MariaDB — mariadb-operator.** Galera for synchronous multi-master across the
three nodes, which maps cleanly onto a 2-of-3 quorum; any node serves. Galera's
cost is real — it dislikes large transactions and DDL, and carries SST/IST
mechanics — so async primary-replica with operator-driven failover is the lighter
alternative where zero-downtime writes are not required. Either way, replica-1
storage under each instance.

Storage HA and backups are orthogonal: the choice above is unaffected by how
backups are taken.

## Backups are logical dumps to S3

Backups are **logical dumps** — `pg_dump`/`pg_dumpall` and `mariadb-dump` — landed
in a Garage bucket. This is a deliberate fit to how the databases are actually
used here: the common operation is pulling a dump and browsing it, table by
table, which a logical dump serves and a physical or snapshot backup cannot. Full
restores are rare.

CNPG's snapshot/WAL machinery and MariaDB physical backups are **not** used. They
give faster large-scale restore and point-in-time recovery, but neither is
browseable, and PITR is not what this workload needs.

### Automate the cadence, keep manual on top

Dumps run on a schedule so the floor is guaranteed; ad-hoc manual dumps layer on
for the browse workflow. A manual-only backup rots exactly when it is needed.

- **Postgres:** CNPG has no native logical dump, so a `CronJob` runs
  `pg_dumpall --globals-only` plus a per-database `pg_dump -Fc`, piped to S3. It
  targets the **replica** service, not the primary.
- **MariaDB:** the mariadb-operator `Backup` CRD does scheduled logical backups to
  S3 directly. A `CronJob` with `mariadb-dump` is the fallback.

### Get the dump flags right or the dump lies

- `pg_dump` is already transactionally consistent without locking, but a
  per-database dump **excludes roles, grants and tablespaces** —
  `pg_dumpall --globals-only` alongside it is required, or a restore comes up with
  no users.
- `mariadb-dump` needs `--single-transaction` for a consistent InnoDB snapshot
  without locking. It only holds if every table is InnoDB and no DDL runs during
  the dump; without it the dump is torn.

### Garage is the primary target, the cloud is the real backup

Garage is off-cluster — it survives a full cluster wipe — but it is a single node
at `replication_factor = 1`, and `docs/garage-buckets.md` states plainly that
nothing in it is backed up by being there. The durable copy is Garage's own
backup to the cloud.

Two constraints make that chain trustworthy:

- **Retention on Garage must outlive the cloud sync cadence.** A dump must not
  expire on Garage before the cloud job has copied it.
- **The cloud tier must be versioned or object-locked.** A logical dump faithfully
  captures a `DROP TABLE` or a corrupt export and syncs it upward; immutability
  plus a few generations is what separates a backup from a copy.

Add a Garage bucket per engine the way the LGTM stack does — an entry in the
`buckets` map in `terraform/garage-buckets`, credentials consumed through an
`ExternalSecret`.

## The tradeoff being accepted

Logical dumps mean an RPO of the dump interval — up to one interval's writes lost
— and a slow, coarse restore: a logical reload rebuilds every index and replays
every row, which on a large database is measured in hours. Restores are rare here,
which is precisely why they tend to be emergencies; the recovery is slow when it
comes. This is a chosen tradeoff for a browse-heavy workflow, not an oversight.

## Longhorn interactions to handle before rollout

- **Exclude database volumes from the `default` recurring-job group.** The jobs in
  `flux/config/longhorn/recurring-jobs.yaml` snapshot and back up every default
  volume. Replica-1 database volumes would collect crash-consistent block backups
  that are redundant with the logical dumps and waste disk — put them on a storage
  class or recurring-job group that opts out.
- **The Longhorn `backupTarget` is unset.** The existing `weekly-backup` job has
  nowhere to write. Independent of the database design, but worth resolving while
  backup targets are being thought about.

## Test versus production

The current cluster is a test bed — three nodes with a ~10 GiB Longhorn data disk
each. The production cluster is sized far larger, so the disk-pressure and
per-node footprint concerns of running two HA engines plus the LGTM stack do not
carry over. The design above is written for production; on the test cluster, size
PVCs down accordingly.
