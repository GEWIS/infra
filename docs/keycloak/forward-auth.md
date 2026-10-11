# Forward auth

Apps protected by Keycloak use the Traefik plugin `traefik-oidc-auth`, loaded in
`flux/20_controllers/traefik/helm-release.yaml` and pinned to `v0.18.0`, the
version the old cluster ran. Every Middleware that still has to move was written
against it. `v0.21.0` splits `UnauthorizedBehavior`, so upgrade only once all
consumers are here.

On the old cluster every app shared one client, `traefik-auth`, and the
reflector copied its secret from `shared-secrets/oidc-auth` into each namespace.
Here, every app gets its own client.

## Clients are a map

`terraform/50_keycloak-config` declares the clients in `forward_auth_clients` in
`locals.tf`:

```hcl
webhost-prod = {
  namespace     = "webhost-prod"
  redirect_uris = ["https://abc.gewis.nl/admin/oidc/callback", ...]
}
```

Each entry creates:

- a confidential `GEWISWG` client named after the key, with the standard flow
  only and exactly these redirect URIs, whose description says OpenTofu
  manages it, so nobody edits it by hand in the admin console
- a `groups` mapper that puts group names without their path in the ID token,
  access token and userinfo
- a 64-character client secret and a 32-character plugin secret, which the
  plugin uses to encrypt its session cookie
- OpenBao `keycloak/<namespace>/<client>` holding `client_id`,
  `providerClientSecret` and `pluginSecret`, with a read policy for that path
- the Kubernetes auth role `keycloak-<namespace>`, bound to every
  ServiceAccount in that namespace

The plugin validates the ID token by default, and Keycloak always puts the
client ID in its `aud`. So `ValidAudience` is the client ID and the client needs
no audience mapper.

## What a consuming namespace adds

Traefik resolves `urn:k8s:secret:` only in the Middleware's own namespace, so
each namespace builds its own `oidc-secret`:

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: keycloak
---
apiVersion: external-secrets.io/v1
kind: SecretStore
metadata:
  name: keycloak
spec:
  provider:
    vault:
      server: http://openbao-active.openbao.svc:8200
      path: keycloak
      version: v2
      auth:
        kubernetes:
          mountPath: kubernetes
          role: keycloak-<namespace>
          serviceAccountRef:
            name: keycloak
---
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: oidc-secret
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: keycloak
    kind: SecretStore
  target:
    name: oidc-secret
  dataFrom:
    - extract:
        key: <namespace>/<client>
```

The Middleware then uses the per-app client:

```yaml
plugin:
  traefik-oidc-auth:
    Provider:
      Url: https://auth.gewis.nl/realms/GEWISWG
      ClientId: <client>
      ValidAudience: <client>
      ClientSecret: urn:k8s:secret:oidc-secret:providerClientSecret
    Secret: urn:k8s:secret:oidc-secret:pluginSecret
```

Apps deployed from `k8s-apps` apply these objects as `app-deployer`. That Role
needs `secretstores` and `externalsecrets` in `external-secrets.io`. The webhost
chart still renders an empty `oidc-secret` with a reflector annotation, and that
has to become the objects above, with `clientId` and `validAudience` both set to
the release's client. The chart's default for both is `traefik-auth`, which
fails every login against a per-app client.

`webhost_prod_hosts` in `locals.tf` copies the domains and `adminDomain`s from
`k8s-apps/webhost/prod/release.yaml`. A new one needs a line there and a
`tofu apply`, or its `/admin` login fails with Keycloak's "Invalid redirect
uri".
