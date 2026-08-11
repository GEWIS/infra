# Routing is Gateway API on Cilium

Cilium is the Gateway API implementation (`gatewayClassName: cilium`). It is not a
Flux controller: Gateway API is part of the CNI and is switched on with
`gatewayAPI.enabled` in the Cilium Helm values in
`terraform/talos-bootstrap/main.tf`. Every node then runs an Envoy that eBPF
transparently forwards matching traffic into.

The `Gateway` itself is ours, in `flux/config/gateway/` — named `gateway` in the
`gateway` namespace, so an `HTTPRoute` reads:

```yaml
parentRefs:
  - name: gateway
    namespace: gateway
```

There is **one listener**, HTTPS on 443. No plaintext listener exists, because
the router forwards nothing to port 80 — see
[Ingress](../talos/ingress.md). A single listener also means a route needs no
`sectionName`: with a `:80` listener present, a route naming a hostname would
attach to it as well and win over any redirect on specificity, serving the app
in plaintext to anything that reached the node directly.

An HTTPS listener **requires** `tls.certificateRefs` — nested under `tls`, not
beside `port` — and there is no fallback to a self-signed certificate. Cilium's
Envoy does not read that secret from the
`gateway` namespace: `cilium-operator` copies it into `cilium-secrets` and Envoy
loads it from there over SDS, which is how Envoy stays without cluster-wide
secret access. Keeping the `Certificate` in the same namespace as the `Gateway`
also avoids needing a `ReferenceGrant`.

## Authentication is a route filter, not an implementation detail

Cilium 1.20 added the `ExternalAuth` HTTPRoute filter from
[GEP-1494](https://gateway-api.sigs.k8s.io/geps/gep-1494/), which delegates the
allow/deny decision to a service over Envoy's `ext_authz` protocol. The field
exists only in the experimental channel of the Gateway API CRDs, which is what
the `crds` layer installs.

Nothing uses it. authentik, Grafana and OpenBao each authenticate themselves —
Grafana against authentik over OIDC. It is the seam that keeps the routing layer
replaceable: a workload without a login of its own gets a filter on its own
route, in portable Gateway API config, rather than a middleware belonging to one
implementation.
