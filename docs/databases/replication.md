# Replicate at the database layer, never at both

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
