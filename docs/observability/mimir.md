# Mimir is hand-written, and that is the smaller option

`mimir-distributed` is microservices-only — upstream says so outright — and as of
chart 6.1.0 it defaults to the Kafka ingest-storage architecture: `kafka.enabled:
true`, with `ingest_storage: enabled: true` written unconditionally into the
config and `ingester.push_grpc_method_enabled: false`. Disabling Kafka only drops
the broker address; the ingester still refuses gRPC pushes. Running it here would
mean a Kafka StatefulSet plus ten services plus four memcached tiers on three
nodes.

Monolithic mode is one flag, `-target=all`, which runs QueryFrontend,
QueryScheduler, Querier, Ingester, Distributor, StoreGateway, **Ruler** and
**Compactor** (`pkg/mimir/modules.go`). Alertmanager is not part of `all`, so the
target is `all,alertmanager` — see [Alerting](alerting.md).

Blocks live in the `mimir` bucket under `storage_prefix: blocks`. That field
"may only contain digits and English alphabet letters", so a path like
`mimir/blocks` is rejected. Rules and Alertmanager configuration are not in the
bucket at all: both read from ConfigMaps on disk.

Monolithic does not forfeit HA. Upstream supports scaling it horizontally, so the
rings use **memberlist from day one** rather than `inmemory`; going to three
replicas is `replicas: 3` plus `replication_factor: 3`, not a re-architecture.
The same holds for Loki's SingleBinary mode. Tempo's single-binary chart has no
ring, so scaling *it* means moving to `tempo-distributed` — cheap, since the
blocks are already in S3.

## Mimir is configured entirely by flags, deliberately

The main configuration has no ConfigMap. Every setting is a container argument, which means the
configuration *is* the pod spec: Flux applies a change, the StatefulSet's
template changes, and the pod rolls. A config file in a ConfigMap would be
applied silently and never restart anything — Mimir has no hot reload for its
main config — and the usual fix, a hashed `configMapGenerator`, needs a
`kustomization.yaml` that this tree deliberately does not have, since every layer
here relies on Flux's recursive scan. Rules and Alertmanager routing are the
exception, because Mimir does re-read those from disk on its own poll.

The cost is that the two S3 keys reach the process through `$(VAR)` argument
expansion, so kubelet writes them into the container's argv. The manifest itself
holds only the placeholder, and the values come from the ESO-managed Secret via
`secretKeyRef` — but anyone who can `exec` into the pod can read them from
`/proc`, which is also true of the environment-variable form.

Per-tenant limits, when they arrive, belong in a runtime configuration file
rather than here: that one Mimir *does* reload without a restart.
