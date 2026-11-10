# Container registry

[zot](https://zotregistry.dev) at `https://registry.gewis.nl`, which serves
only logged-in identities: GitHub Actions push with their own OIDC token, and
people log in through Keycloak for the UI and API keys. On the LAN,
`registry.net.gewis.nl` logs every pull in as a read-only user, so nodes need
no credentials.

| Piece | Where |
| --- | --- |
| HelmRelease `zot` (chart `zot`), HelmRelease `zot-values` with zot's config in `config.yaml`, HelmRelease `zot-app-access`, routes, password and session-key generators, S3 and OIDC `ExternalSecret`s | `flux/50_apps/zot/`, in the `apps` layer |
| Policies from the publishers and app lists, the htpasswd file and the LAN Middleware | local chart `charts/zot-values`, see [The config](config.md) |
| Trusted publishers: repository, workflow, environment, image paths | `flux/50_apps/zot/publishers.yaml`, see [Publishing](publishing.md) |
| App groups that manage `<app>/` | the [app access](../cluster/app-access.md) list, see [Login](login.md) |
| Traefik's `internal` entrypoint, its LoadBalancer `10.82.50.16` and the `internal.net.gewis.nl` record | `flux/20_controllers/traefik/helm-release.yaml` |
| Bucket `zot` and its credentials at `seaweedfs/zot/zot` | `terraform/40_seaweedfs-buckets` |
| Keycloak client `zot`, callback `https://registry.gewis.nl/zot/auth/callback/oidc`, credentials at `keycloak/zot/zot` | `terraform/50_keycloak-config` |
| `registry.net.gewis.nl` → `internal.net.gewis.nl` → `10.82.50.16`, public | external-dns, from the `zot-lan` route and the `traefik-internal` Service; the name is in the default [certificate](../cluster/certificates.md) |

zot fetches Keycloak's discovery document at startup and exits until it
answers.

None of the cluster's own components pull from it: zot itself (from
`ghcr.io`), Traefik, Longhorn, SeaweedFS and CoreDNS come from elsewhere. zot
grants nothing anonymously; only the LAN route logs requests in for the client,
as the read-only `lan-reader`, see [LAN login](lan-login.md).
