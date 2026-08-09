# CBC infra

Operational documentation for the GEWIS CBC infrastructure: the NixOS hosts, the
OpenTofu that provisions them, and the Flux GitOps tree reconciled into the Talos
Kubernetes cluster.

## Hosts

| Host | Role |
| --- | --- |
| [pcgewisinfo](pcgewisinfo/index.md) | Info-screen kiosk; DHCP and print server for the booth LAN |
| [s3-01](s3-01/index.md) | Garage S3 object store, single node |
| [talos](talos/index.md) | 3-node Talos Kubernetes cluster |

## Inside the cluster

| Topic | What it covers |
| --- | --- |
| [cluster](cluster/index.md) | Flux layering, ingress, certificates, DNS, OpenBao |
| [databases](databases/index.md) | HA Postgres and MariaDB placement and their backup model |
| [authentik](authentik/index.md) | The identity provider and how it is wired up |
| [observability](observability/index.md) | The LGTM stack and its tenancy model |
| [garage-buckets](garage-buckets/index.md) | S3 buckets and the credentials the cluster reads for them |

The repository itself, its layout, and how to work on it are in the
[README](https://github.com/GEWIS/infra#readme).
