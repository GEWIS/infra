# The stack per engine

**Postgres — CloudNativePG.** Three instances, one primary and two replicas, each
its own PVC on the replica-1 class. Streaming replication, automatic failover in
seconds, a lost replica rebuilt from its peers. The operator makes the
three-instance layout nearly free to run.

**MariaDB — mariadb-operator.** Three pods, one primary and two replicas, each on
its own replica-1 PVC. Semi-synchronous replication, automatic failover by the
operator. A replica that loses its place in the binary log is rebuilt from a
fresh physical backup of a ready replica (`replica.recovery` with the
`mariadb-replica` `PhysicalBackup` template). It is the same layout as Postgres,
and it is the topology the operator supports point-in-time recovery on.

Storage HA and backups are orthogonal: the choice above is unaffected by how
backups are taken.
