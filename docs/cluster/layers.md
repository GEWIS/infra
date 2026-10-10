# Layers exist to order secrets and readiness, nothing else

```
sealed-secrets ─→ controllers ─→ config ─┬─→ services ─→ apps
                                └→ openbao ┘
```

The two-digit prefix on each directory mirrors the graph: lower reconciles first,
layers with the same prefix are independent. Only the directory carries it — the
`Kustomization` names stay bare, and renaming one would make its parent prune it
together with everything it applied.

| Layer | Path | Holds |
| --- | --- | --- |
| `sealed-secrets` | `flux/10_sealed-secrets/` | the sealed-secrets controller |
| `controllers` | `flux/20_controllers/` | cert-manager, external-dns, Traefik, longhorn, external-secrets, cloudnative-pg, mariadb-operator with the `ServiceMonitor` CRDs |
| `config` | `flux/30_config/` | ClusterIssuer, the wildcard Certificate, Longhorn jobs and storage classes, the kube-system Corefile, `cluster-admin` for `CBC - Application Hosting Team (ADM)` |
| `openbao` | `flux/30_openbao/` | OpenBao, its IngressRoute, its seal secret |
| `services` | `flux/40_services/` | the resolver, the node exporter, the Postgres and MariaDB clusters |
| `apps` | `flux/50_apps/` | authentik, the LGTM stack, Kite, the Hubble and Flux UI routes |

Three dependencies carry real weight and none is cosmetic:

- **`controllers` depends on `sealed-secrets`** because it applies `SealedSecret`
  objects, so the CRD and its decryptor must already exist. Traefik's CRDs need
  no layer of their own: the chart installs them (`crds: CreateReplace`) in
  `controllers`, so every later layer can carry `IngressRoute`s.
- **`services` depends on `openbao`** because Postgres and MariaDB read their
  backup bucket credentials through `ExternalSecret`s. External Secrets retries until OpenBao
  answers, so this is not a correctness requirement — but with `wait: true` the
  layer would otherwise sit un-`Ready` through the whole of OpenBao's first boot,
  which reads as a broken deploy rather than an ordered one. On a fresh cluster
  the same `ExternalSecret` also waits for `terraform/40_seaweedfs-buckets` to
  write the key, so `services` — and `apps` behind it — are not `Ready` until
  that root has been applied.
- **`apps` depends on `services`** for the same reason, one level up. A database
  consumer starts, fails to connect and backs off until its database exists, so
  this is a soft dependency too — but keeping the consumers in the leaf layer
  means their flapping never holds up the substrate below them.

The split between `services` and `apps` is worth stating plainly, because it is
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
`terraform/20_talos-bootstrap/sealed-secrets.tf`.
