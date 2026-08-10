# Layers exist to order CRDs and secrets, nothing else

```
crds ───────────┐
                ├─→ controllers ─→ config ─┬─→ services ─→ apps
sealed-secrets ─┘                └→ openbao ┘
```

| Layer | Path | Holds |
| --- | --- | --- |
| `crds` | upstream `gateway-api` | Gateway API CRDs |
| `sealed-secrets` | `flux/sealed-secrets/` | the sealed-secrets controller |
| `controllers` | `flux/controllers/` | cert-manager, external-dns, longhorn, external-secrets, cloudnative-pg |
| `config` | `flux/config/` | ClusterIssuer, wildcard Certificate, the Gateway, Longhorn jobs and storage classes, the kube-system Corefile |
| `openbao` | `flux/openbao/` | OpenBao, its HTTPRoute, its seal secret |
| `services` | `flux/services/` | the resolver, the node exporter, the Postgres cluster |
| `apps` | `flux/apps/` | authentik, the LGTM stack |

Four dependencies carry real weight and none is cosmetic:

- **`controllers` depends on `crds`** so that the Gateway API CRDs land ahead of
  `config`, which holds the `Gateway`. Nothing in `controllers` itself needs them
  any more — the edge stays because every later layer inherits it, and a `Gateway`
  applied without its CRD is not a degraded object but a rejected one. The
  matching `GatewayClass` comes from Cilium, which OpenTofu installs, so the layer
  graph does not order it at all: Cilium disables Gateway API support for each CRD
  it cannot find.
- **`controllers` depends on `sealed-secrets`** because it now applies
  `SealedSecret` objects, so the CRD and its decryptor must already exist.
- **`services` depends on `openbao`** because the observability stack reads its S3
  credentials through an `ExternalSecret`. External Secrets retries until OpenBao
  answers, so this is not a correctness requirement — but with `wait: true` the
  layer would otherwise sit un-`Ready` through the whole of OpenBao's first boot,
  which reads as a broken deploy rather than an ordered one.
- **`apps` depends on `services`** for the same reason, one level up. A database
  consumer starts, fails to connect and backs off until its database exists, so
  this is a soft dependency too — but keeping the consumers in the leaf layer
  means their flapping never holds up the substrate below them.

The split between the last two layers is worth stating plainly, because it is
not about ordering. What a layer buys, once CRDs and secrets are accounted for,
is the blast radius of `wait: true`: a Kustomization is un-`Ready` until every
object in it is healthy. `services` holds what other things consume, `apps`
holds the consumers, and nothing depends on `apps` — so an app waiting on its
database is a fact about that app rather than a stalled cluster.

SealedSecrets live next to the chart that consumes them rather than in a central
secrets directory. That works only because the decryptor is hoisted into its own
earlier layer: a SealedSecret in the *same* layer as the sealed-secrets
controller is a race, whereas one in a *later* layer decrypts within a second.

Do not put a secret in a layer that depends on the layer consuming it. external-dns
takes its Cloudflare token as a startup environment variable, so with its secret
in `config` the pod blocks on `CreateContainerConfigError` → the HelmRelease never
goes `Ready` → `controllers` never goes `Ready` → `config` never applies → the
secret is never created. A clean deadlock. cert-manager tolerates the same
placement only because its pods start fine without the token; it is read later,
at `Certificate` reconcile.

The `sealed-secrets` **namespace** is created by OpenTofu, not Flux, so the
sealing key can be pinned and survive a cluster rebuild — see
`terraform/talos-bootstrap/sealed-secrets.tf`.
