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
**Compactor** (`pkg/mimir/modules.go`). Two consequences:

- Ruler is included, so `ruler_storage` must be configured or the process fails.
- Alertmanager is not, so alertmanager storage is skipped entirely.

Both live in the one `mimir` bucket, separated by `storage_prefix`. That field
"may only contain digits and English alphabet letters", so the prefixes are
`blocks` and `ruler` — a path like `mimir/blocks` is rejected.

Monolithic does not forfeit HA. Upstream supports scaling it horizontally, so the
rings use **memberlist from day one** rather than `inmemory`; going to three
replicas is `replicas: 3` plus `replication_factor: 3`, not a re-architecture.
The same holds for Loki's SingleBinary mode. Tempo's single-binary chart has no
ring, so scaling *it* means moving to `tempo-distributed` — cheap, since the
blocks are already in S3.

## Mimir is configured entirely by flags, deliberately

There is no ConfigMap. Every setting is a container argument, which means the
configuration *is* the pod spec: Flux applies a change, the StatefulSet's
template changes, and the pod rolls. A config file in a ConfigMap would be
applied silently and never restart anything — Mimir has no hot reload for its
main config — and the usual fix, a hashed `configMapGenerator`, needs a
`kustomization.yaml` that this tree deliberately does not have, since every layer
here relies on Flux's recursive scan.

The cost is that the two S3 keys reach the process through `$(VAR)` argument
expansion, so kubelet writes them into the container's argv. The manifest itself
holds only the placeholder, and the values come from the ESO-managed Secret via
`secretKeyRef` — but anyone who can `exec` into the pod can read them from
`/proc`, which is also true of the environment-variable form.

Per-tenant limits, when they arrive, belong in a runtime configuration file
rather than here: that one Mimir *does* reload without a restart.
