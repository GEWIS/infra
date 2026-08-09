# Routing is Gateway API, auth would be Traefik

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
