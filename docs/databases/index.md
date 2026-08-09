# databases

How HA Postgres and MariaDB are placed on this cluster, why the redundancy lives
where it does, and how they are backed up.

Postgres is deployed: one CloudNativePG cluster in the `postgres` namespace,
reconciled by the `services` layer, with per-application roles and databases
declared beside it. MariaDB is still design only — the pages on replication,
backups and the tradeoff describe both engines and the build follows them.
