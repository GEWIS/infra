# NetBird runs in the cluster

The NetBird control plane for `nb.gewis.nl` — management, signal, relay and STUN
in one `netbird-server` pod, the dashboard, and the reverse proxy behind
`print.gewis.nl` — is installed by `flux/50_apps/netbird/`. Every NetBird peer
(admins, s3-01, the service PCs) is enrolled with it.

## Routes

| Path on `nb.gewis.nl` | Backend |
| --- | --- |
| `/relay`, `/ws-proxy`, `/oauth2`, `/api` | `netbird-service:80` |
| `/signalexchange.SignalExchange`, `/management.ManagementService`, `/management.ProxyService` | `netbird-service:81`, `scheme: h2c` (gRPC) |
| everything else | `dashboard:80` |

`/oauth2` is NetBird's embedded identity provider; the dashboard logs in against
it. `nb.gewis.nl` is covered by the default `*.gewis.nl` certificate in Traefik's
TLS store. The routes carry no external-dns annotation: the record predates
external-dns and is not owned by it.

STUN is UDP 3478 on its own LoadBalancer IP, **`10.82.50.14`**. router02 forwards
public UDP 3478 there.

`print.gewis.nl` is an `IngressRouteTCP` with TLS passthrough to the reverse proxy
on `:8443`, which terminates TLS itself with the `*.gewis.nl` certificate
`netbird-reverse-proxy-tls` and does its own SSO. Every exposed host must be its
own `HostSNI` match; a wildcard SNI would capture every other `*.gewis.nl` route.

## State

| What | Where |
| --- | --- |
| Accounts, peers, policies | Postgres database `netbird` from `terraform/40_databases`, reached at `postgres.net.gewis.nl` with `sslmode=verify-full`; credentials via the `postgres` SecretStore |
| Server data directory | Longhorn volume `netbird-data`, bound by a static PV/PVC in `volume.yaml` with `persistentVolumeReclaimPolicy: Retain` |
| `config.yaml`, including the store encryption key | SealedSecret `netbird-config` |
| Reverse-proxy token | SealedSecret `netbird-reverse-proxy-token` |

The store encryption key in `config.yaml` encrypts fields in the database; the
database is unreadable without that exact key, so the two are only ever moved
together.

The PV names the Longhorn volume by `volumeHandle: netbird-data` rather than
letting a PVC provision one, so the volume can be restored from a backup under
that name and the pod picks it up; until it exists, the pod waits in
`ContainerCreating`.

Images are pinned (`netbird-server` and `reverse-proxy` `0.78.2`, dashboard
`v2.92.0`); the server migrates the database schema on startup, so a bump is a
one-way step.

## Operator and network router

`flux/20_controllers/netbird-operator/` installs the NetBird operator (chart
`0.8.0`) into `netbird-operator`, talking to `https://nb.gewis.nl` with the API
key in SealedSecret `netbird-mgmt-api-key` and registering as cluster `gewis`,
the Talos cluster name. It must differ from the previous cluster's operator,
which registers as `gewis-prod`: the name prefixes the networks and resources the
operator creates in NetBird, so two operators sharing it would manage each
other's objects. `flux/30_config/netbird-operator/` holds the `NetworkRouter` `lan`,
which publishes resources under the NetBird DNS zone `k8s.gewis.nl`; that zone
must exist in NetBird before the router reconciles.

The router pod the operator creates runs its `netbird` container with
`privileged: true` and `NET_ADMIN`, `SYS_ADMIN`, `SYS_RESOURCE`. Talos enforces the
`baseline` Pod Security level by default, so the `netbird-operator` namespace is
labelled `pod-security.kubernetes.io/enforce: privileged`; without it the
Deployment's ReplicaSet is refused and no router pod appears.
