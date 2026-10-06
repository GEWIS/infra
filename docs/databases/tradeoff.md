# The tradeoff being accepted

Postgres archives WAL continuously, so it can be recovered to any point inside
the retention window. The cost is that a backup is not browseable: getting one
table out means restoring a whole cluster and dumping from it.

MariaDB is planned with logical dumps, which trade the other way: an RPO of the
dump interval — up to one interval's writes lost — and a slow, coarse restore,
because a logical reload rebuilds every index and replays every row, which on a
large database is measured in hours.
