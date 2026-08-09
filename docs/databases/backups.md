# Backups are logical dumps to S3

Backups are **logical dumps** — `pg_dump`/`pg_dumpall` and `mariadb-dump` — landed
in a Garage bucket. This is a deliberate fit to how the databases are actually
used here: the common operation is pulling a dump and browsing it, table by
table, which a logical dump serves and a physical or snapshot backup cannot. Full
restores are rare.

CNPG's snapshot/WAL machinery and MariaDB physical backups are **not** used. They
give faster large-scale restore and point-in-time recovery, but neither is
browseable, and PITR is not what this workload needs.

## Automate the cadence, keep manual on top

Dumps run on a schedule so the floor is guaranteed; ad-hoc manual dumps layer on
for the browse workflow. A manual-only backup rots exactly when it is needed.

- **Postgres:** CNPG has no native logical dump, so a `CronJob` runs
  `pg_dumpall --globals-only` plus a per-database `pg_dump -Fc`, piped to S3. It
  targets the **replica** service, not the primary.
- **MariaDB:** the mariadb-operator `Backup` CRD does scheduled logical backups to
  S3 directly. A `CronJob` with `mariadb-dump` is the fallback.

## Get the dump flags right or the dump lies

- `pg_dump` is already transactionally consistent without locking, but a
  per-database dump **excludes roles, grants and tablespaces** —
  `pg_dumpall --globals-only` alongside it is required, or a restore comes up with
  no users.
- `mariadb-dump` needs `--single-transaction` for a consistent InnoDB snapshot
  without locking. It only holds if every table is InnoDB and no DDL runs during
  the dump; without it the dump is torn.

## Garage is the primary target, the cloud is the real backup

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
