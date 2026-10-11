# Keycloak

GEWIS SSO at `https://auth.gewis.nl`, realm `GEWISWG`, with the admin console on
`https://auth-admin.gewis.nl`. `flux/50_apps/keycloak/` deploys it in the `apps`
layer. The manifests came from `GEWIS/internal-systems` (`keycloak/`), and Flux
adopted the copy that was applied there by hand during the migration.

Keep the namespace `keycloak-prod` and the object names. The Deployment
`keycloak`, the PVCs `kerberos` and `logs` and the selector
`io.kompose.service: keycloak` match the live objects, so Flux takes them over
instead of creating new ones. The SealedSecret `keycloak-secrets` is sealed
namespace-wide for `keycloak-prod`, so renaming the namespace also means
resealing it.

| Piece | Where |
| --- | --- |
| Database | external, `mariadb01.db.gewis.nl/auth_prod` |
| Admin account and database login | SealedSecret `keycloak-secrets` |
| Kerberos config | PVC `kerberos` (5Mi) |
| File logs | PVC `logs` (100Mi) |

**Only one instance may run against `auth_prod`.** The Deployment uses
`strategy: Recreate` and one replica. Do not start a second copy, not even
briefly in another namespace.

## Routes

`ingressroute.yaml` publishes `auth.gewis.nl` through the TU/e WAF and
`auth-admin.gewis.nl` directly through router02. Neither carries the
external-dns annotation, because both records already exist outside
external-dns.

On `auth.gewis.nl` only the public paths are routed: `/realms/`, `/resources/`,
`/js/`, `/welcome-content/` and `/robots.txt`. The three `keycloak-acr-strip-*`
Middlewares remove `acr_values` from authorization requests. `/` redirects to
the account console. `/health` goes to the management port and only accepts the
two monitoring addresses in `keycloak-health-allow`.

Forward auth for other apps uses clients in this realm, see
[Forward auth](forward-auth.md).
