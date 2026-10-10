# databases

How HA Postgres and MariaDB are placed on this cluster, why the redundancy lives
where it does, and how they are backed up.

Both engines are deployed and reconciled by the `services` layer: one
CloudNativePG cluster in the `postgres` namespace and one mariadb-operator cluster
in the `mariadb` namespace. Applications get a role or user and a database each
from one OpenTofu root, `terraform/40_databases`, and reach the primary by name
over verified TLS.
