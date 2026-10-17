# Applying

`terraform/50_keycloak-config` logs in as the service-account client `opentofu`
in the `master` realm, with `client_credentials`. That client holds the client
roles `manage-clients` and `view-realm` of `GEWISWG-realm`, enough to manage
clients in `GEWISWG` and nothing else.

Its secret is `opentofu-client-secret` in `secrets/keycloak.yaml`, admin-only
through `nix/recipients.nix`. The root's `.envrc` exports it as
`TF_VAR_keycloak_client_secret`, and the OpenBao token as `TF_VAR_bao_jwt`. It
is kept out of the cluster on purpose: `keycloak-secrets` is loaded into the
Keycloak pod with `envFrom`.

The `KC_BOOTSTRAP_ADMIN_*` account is not used. Keycloak reads those variables
only on a first start against an empty database, and that account's password
has since been changed by hand.

The provider talks to `https://auth-admin.gewis.nl`. `auth.gewis.nl` routes only
the public paths, so `/admin/` there is Traefik's `404 page not found`.

```sh
cd terraform/50_keycloak-config
tofu init
tofu apply
```

The apply creates the clients and writes their OpenBao paths. Apply it before
the consuming app arrives. Until the path exists, its `ExternalSecret` fails and
the Middleware has no `oidc-secret` to read.

Check one client end to end once its namespace has the ExternalSecret:

```sh
kubectl -n <namespace> get externalsecret oidc-secret
curl -sI https://<host>/admin/ | grep -i '^location'   # → auth.gewis.nl/realms/GEWISWG/…
```

## Adopting a client that already exists

A client created by hand is imported, not recreated, so its client roles and the
directory mappers that hand them out stay attached. Add `import` blocks to the
root, addressed by the client's internal UUID (`GEWISWG/<uuid>`, mappers
`GEWISWG/client/<uuid>/<mapper-uuid>`), and delete them after the apply that
imported them.

That apply overwrites what `oidc.tf` declares: the client secret becomes the
generated one, and redirect URIs, direct access grants, default scopes, name and
description are reset. Attributes it does not declare, such as consent and web
origins, keep their hand-set values.

An app that already has users from another IdP sees a different `sub` for each of
them. Grafana matches users by `sub` only, so after moving it from authentik its
existing OAuth users were deleted through the admin API and recreated on their
next login.
