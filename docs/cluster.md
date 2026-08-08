# cluster

What runs *inside* the Talos cluster, and how Flux orders it. The cluster itself
— VMs, machine config, CNI — is [`docs/talos.md`](talos.md).

Everything here is reconciled by Flux from `flux/`, with one `Kustomization` per
layer in `flux/clusters/gewis-prod/`.

## Layers exist to order CRDs and secrets, nothing else

```
crds ───────────┐
                ├─→ controllers ─→ config
sealed-secrets ─┘               └─→ openbao
```

| Layer | Path | Holds |
| --- | --- | --- |
| `crds` | upstream `gateway-api` | Gateway API CRDs |
| `sealed-secrets` | `flux/sealed-secrets/` | the sealed-secrets controller |
| `controllers` | `flux/controllers/` | cert-manager, traefik, external-dns, longhorn, external-secrets |
| `config` | `flux/config/` | ClusterIssuer, wildcard Certificate, Longhorn jobs |
| `openbao` | `flux/openbao/` | OpenBao, its HTTPRoute, its seal secret |

Two dependencies carry real weight and neither is cosmetic:

- **`controllers` depends on `crds`** because Traefik's Helm chart renders a
  `Gateway` and `GatewayClass`. Those are custom resources; without the CRDs the
  *whole release* fails to install, not just the Gateway.
- **`controllers` depends on `sealed-secrets`** because it now applies
  `SealedSecret` objects, so the CRD and its decryptor must already exist.

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

## Gateway API is an add-on, and its version must match Traefik

Gateway API is **not** part of Kubernetes and nothing installs it by default —
not Talos, not the Traefik chart (which ships only `traefik.io` CRDs), and not
Cilium unless `gatewayAPI.enabled` is set. It is pulled from upstream by the
`crds` layer via a `GitRepository` pinned to a tag, so Renovate keeps it current;
vendoring the YAML would work too but Renovate cannot bump a static blob.

**Pin the version to what the controller wants, not to whatever is newest-looking.**
Traefik 3.7.5 watches `TLSRoute` and `BackendTLSPolicy` at `gateway.networking.k8s.io/v1`.
Gateway API v1.2.1 serves those at `v1alpha2`/`v1alpha3`, so its informers fail
with *"the server could not find the requested resource"* — indistinguishable
from the CRDs being absent. The provider then never syncs, so:

```
GatewayClass  Accepted=Unknown  "Waiting for controller"
Gateway       Programmed=Unknown
HTTPRoute     status: <empty>
```

and external-dns, which reads targets from an HTTPRoute's `status.parents`,
silently emits nothing. v1.6.1 serves both at `v1` and fixes it.

Use the **experimental** channel. Traefik watches those kinds regardless of the
chart's `experimentalChannel: false`, so the CRDs must exist either way; the
channel is a strict superset of standard.

Traefik does not rebuild its Gateway API informers after startup — installing the
CRDs under a running Traefik changes nothing until the pods restart.

## Routing is Gateway API, auth would be Traefik

Traefik is the Gateway API implementation (`gatewayClassName: traefik`) and the
chart creates a Gateway named `traefik-gateway` in the `traefik` namespace. That
name is hardcoded in the chart, not derived from the release name, so an
`HTTPRoute` can rely on it:

```yaml
parentRefs:
  - name: traefik-gateway
    namespace: traefik
```

Routing lives in portable `HTTPRoute` objects so the implementation can be
swapped later. Authentication cannot be portable: Gateway API has no auth filter,
and Cilium's Gateway API has no OIDC at all — the open request is cilium#31604.
The workarounds (hand-written `CiliumEnvoyConfig` with `ext_authz`, or a separate
`oauth2-proxy`) are fragile, so OIDC stays on Traefik `Middleware` attached via
`ExtensionRef`. That seam is the one deliberately non-portable part.

A Gateway HTTPS listener **requires** `certificateRefs`; unlike a classic Traefik
entrypoint it will not fall back to a self-signed certificate.

## Certificates

cert-manager issues a single wildcard, `*.cbc.gewis.nl`, into the `traefik`
namespace, referenced both by the Gateway listener and by `tlsStore.default` so
it is the default certificate for classic IngressRoutes too.

`--dns01-recursive-nameservers-only` is required on campus, which blocks direct
queries to authoritative nameservers.

A dedicated subdomain matters. `fleet-infra` already issues `*.gewis.nl` from the
same Cloudflare zone; two cert-managers writing `_acme-challenge.gewis.nl` would
race and can break the other cluster's renewals. `*.cbc.gewis.nl` challenges at
`_acme-challenge.cbc.gewis.nl` instead — no collision.

Expect the first issue to be slow. cert-manager's self-check queries the campus
resolver, which caches the pre-creation `NODATA` answer for the zone's SOA
minimum (1800 s). The challenge sits in `pending` with *"not yet propagated"* for
up to 30 minutes and then completes on its own. `presented=true` on the Challenge
with no Cloudflare API errors means the record was written and the wait is purely
cache expiry.

Let's Encrypt caps duplicate certificates at 5/week for an identical name set.
Save `wildcard-cbc-gewis-nl-tls` and restore it into a rebuilt cluster: cert-manager
adopts a valid existing secret and issues nothing.

## DNS

external-dns watches `gateway-httproute` and writes to Cloudflare.

**`domainFilters` must name the Cloudflare zone**, not the subdomain in use. A
zone matches only if it equals the filter or is a subdomain of it, so
`cbc.gewis.nl` excludes the `gewis.nl` zone — external-dns then finds no zone to
write into and reports the very misleading *"All records are already up to date"*.
The filter is `gewis.nl`; scoping comes from ownership instead:

| Setting | Effect |
| --- | --- |
| `txtOwnerId: cbc-test` | only touches records carrying its own ownership TXT |
| `policy: sync` | deletes only records it owns, when their route disappears |
| `txtPrefix: edns-` | keeps the ownership TXT off the CNAME's name, which Cloudflare forbids |

The DNS target is the `external-dns.alpha.kubernetes.io/target` annotation on the
**Gateway**, not on each route — external-dns reads that override from the
Gateway only, and ignores it on an HTTPRoute. It is set once in the Traefik chart
values, so every route inherits it. The target is a hostname, so records are
CNAMEs; with hostPort there is no LoadBalancer address for external-dns to
discover on its own.

`--cloudflare-record-comment` tags every managed record; ownership itself is
still the TXT, not the comment.

## OpenBao

Three-replica Raft, sealed with a static key from a SealedSecret and reached at
`https://openbao.cbc.gewis.nl:8443`.

It self-initialises. Auto-unseal cannot unseal a barrier that was never
initialised, and a StatefulSet will not start pod 1 until pod 0 is `Ready`, so an
uninitialised OpenBao deadlocks at pod 0. The `initialize` stanza breaks that on
first boot, and it only runs against **empty storage** — a partially-initialised
PVC has to be deleted for it to re-run.

Self-init requests take flat values only; a nested map is rejected as `invalid
request`, and a failed request is fatal to the process. The root token is created
and immediately revoked, so the stanza must also provision a way in — here the
Kubernetes auth method bound to the `openbao-admin` ServiceAccount, which avoids
storing an admin password anywhere:

```sh
bao write auth/kubernetes/login role=admin \
  jwt="$(kubectl -n openbao create token openbao-admin)"
```

`.envrc` exports that token as `TF_VAR_bao_jwt` for the `openbao-config` root,
failing quietly when the cluster is unreachable.

`disable_mlock` is not a valid OpenBao 2.x option; it was removed and is only
warned about, not rejected.

## Reading the failure, not the symptom

Several of these surfaced far from their cause. Worth remembering:

- Longhorn pods crash-looping on one node — the node was memory-starved by
  hypervisor ballooning.
- external-dns "up to date" while doing nothing — the zone was filtered out.
- HTTPRoute with an empty `status` — the Gateway controller never started, so
  nothing had accepted the route.
- "Could not connect" in ~15 ms is a TCP reset: the packet arrived and was
  refused. A firewall drop times out instead.
