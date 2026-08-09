# Layers exist to order CRDs and secrets, nothing else

```
crds ───────────┐
                ├─→ controllers ─→ config ─────→ services
sealed-secrets ─┘               └─→ openbao ───────┘
```

| Layer | Path | Holds |
| --- | --- | --- |
| `crds` | upstream `gateway-api` | Gateway API CRDs |
| `sealed-secrets` | `flux/sealed-secrets/` | the sealed-secrets controller |
| `controllers` | `flux/controllers/` | cert-manager, traefik, external-dns, longhorn, external-secrets |
| `config` | `flux/config/` | ClusterIssuer, wildcard Certificate, Longhorn jobs, the kube-system Corefile |
| `services` | `flux/services/` | the resolver, the LGTM stack, the node exporter |
| `openbao` | `flux/openbao/` | OpenBao, its HTTPRoute, its seal secret |

Three dependencies carry real weight and none is cosmetic:

- **`controllers` depends on `crds`** because Traefik's Helm chart renders a
  `Gateway` and `GatewayClass`. Those are custom resources; without the CRDs the
  *whole release* fails to install, not just the Gateway.
- **`controllers` depends on `sealed-secrets`** because it now applies
  `SealedSecret` objects, so the CRD and its decryptor must already exist.
- **`services` depends on `openbao`** because the observability stack reads its S3
  credentials through an `ExternalSecret`. External Secrets retries until OpenBao
  answers, so this is not a correctness requirement — but with `wait: true` the
  layer would otherwise sit un-`Ready` through the whole of OpenBao's first boot,
  which reads as a broken deploy rather than an ordered one.

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
