# The tradeoff being accepted

Both engines archive their logs continuously, Postgres its WAL and MariaDB its
binary logs, so either can be recovered to any point inside the retention window.
The cost is that a backup is not browseable: getting one table out means
restoring a whole cluster and dumping from it.
