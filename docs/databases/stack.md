# The stack per engine

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
