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

## Interim: public 443 still lands on the previous cluster

router02 forwards public `:443` to the previous cluster's Traefik, which still
serves the other `*.gewis.nl` apps. In its `netbird` namespace an `IngressRouteTCP`
`new-cluster-passthrough` passes `HostSNI(nb.gewis.nl)` and
`HostSNI(print.gewis.nl)` through untouched to `10.82.50.10:443`, via a
selectorless Service and an EndpointSlice `new-cluster-traefik`. The endpoint
carries `conditions.ready: true`; without it Traefik treats the Service as empty
and drops the connection mid-handshake.

A browser that already holds an HTTP/2 connection to that Traefik for another
`*.gewis.nl` host reuses it for `nb.gewis.nl`, so the request never shows its SNI
and gets the previous Traefik's `404 page not found`. NetBird clients are not
affected. This section goes away when router02's `:443` moves to `10.82.50.10`.

The previous cluster's `apps` Kustomization, which still holds the old NetBird
manifests, stays suspended with `flux suspend ks apps`. A `kubectl patch` of
`spec.suspend` does not hold: the parent `flux-system` Kustomization's apply strips
fields owned by kubectl, `apps` resumes, and it puts the old routes back in front
of the passthrough.

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
