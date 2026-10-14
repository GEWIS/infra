# Kite is the cluster UI

[Kite](https://github.com/kite-org/kite) at `https://kite.gewis.nl` is
where people look at the cluster. It is a single pod with a SQLite database on a
Longhorn volume, installed by `flux/50_apps/kite/` from
`oci://ghcr.io/kite-org/charts`. Its clusters, login, roles and local admin come
from the Secret `kite-roles`, which [app access](app-access.md) renders; the UI
shows those sections read-only. The chart mounts the Secret as a directory, so
Kite picks up a new version without a restart.

## Permissions are Kite's own, capped by its service account

Kite does not pass the user's identity to the apiserver. It talks to the cluster
with its own service account and checks every request against its own roles
first. Two limits apply, and the stricter one wins:

| Layer | Defined in | Allows |
| --- | --- | --- |
| Kite's service account | `rbac.rules` | read everything, `delete` pods, `create` on `pods/exec`, nothing else, for anyone |
| Kite roles | `config.rbac.roles` | per role: namespaces, resources and verbs (`get`, `log`, `exec`, `delete`, …) |

Even a bug in Kite's own checks cannot change anything but pods, and Flux stays
the only writer of every other object. `pods/exec` still lets a user change
things *inside* a running container.

Roles are mapped to AD groups from the `groups` claim, and Kite replaces every
role assignment with the configured ones on each reload:

| Role | Mapped to | Grants |
| --- | --- | --- |
| `admin` (built in) | `CBC - Application Hosting Team (ADM)` | everything Kite's service account can do |
| `crd-reader` | every logged-in user | `get` on `crds`, cluster-scoped only |

Every custom resource page loads its CustomResourceDefinition first, and Kite
checks cluster-scoped requests against the namespace `_all`, which is the only
namespace `crd-reader` lists. The namespace selector shows a namespace when one
of the user's roles lists it, so `crd-reader` adds none. It covers the
definitions, not the objects in them.

Each entry in the [app access](app-access.md) list gets two roles for its
group: `<app>-read` with `get` and `log` on every resource, and `<app>-pods`
with `exec` and `delete` on `pods`, both limited to the entry's namespaces.
Kite then offers delete only on pods. A user with no app role sees CRD
definitions and nothing else.

## What a user sees

The namespace selector, the all-namespaces lists and the global search only
return namespaces the user's roles allow; Kite filters them server-side. The
sidebar is Kite's default and is not filtered: kinds outside a user's role, such
as Nodes, are listed and open to an error page. CRDs such as Traefik, Longhorn,
CloudNativePG and Flux objects are reached through *Custom Resource
Definitions*.

## Login and keys

Login goes through Keycloak, realm `GEWISWG`. The `kite` client comes from
`oidc_clients` in `terraform/50_keycloak-config`; an `ExternalSecret` brings its
secret from OpenBao `keycloak/kite/kite` into `kite-oidc`, and Kite reads it as
`${OAUTH_CLIENT_SECRET}` in its config. `host` carries `https://`, since Kite
builds the callback URL `/api/auth/callback` from it. The `groups` claim lists
AD group names without a path, nested membership included, because the realm's
`group-mapper` reads `memberOfFlattened`; it covers only groups under
`OU=Groups`.

Kite reads `OAUTH_CLIENT_SECRET` from its environment, which is set only when
the pod starts. After the secret changes, wait until the `kite-oidc`
ExternalSecret is synced, then run `kubectl -n kite rollout restart deploy/kite`.

`JWT_SECRET` and `KITE_ENCRYPT_KEY` are generated once in the cluster by an
External Secrets `Password` generator with `refreshPolicy: CreatedOnce`.

The config declares one local user, `admin`, with a password from a second
`Password` generator in the `kite-admin` Secret. Kite needs a user before it
leaves its first-run setup. No person uses it: login is Keycloak only, and when
Keycloak is down the Talos break-glass kubeconfig is the way in.

## Plugins and login settings

Kite keeps installed plugins and its login settings in its database rather than
its config file. The CronJob `kite-plugins` (`plugins.yaml`) repairs both every
15 minutes through Kite's admin API:

- it installs and enables the plugins listed by catalog id and version in the
  `plugins.json` key of the `kite-plugins` ConfigMap;
- it sets `passwordLoginDisabled: true` and `enablePasskeyLogin: false`, so the
  login page offers only Keycloak.

With password login off, the job authenticates with an API key, user
`kite-plugins`, which the generated config maps to `admin`. The key lives in the
Secret `kite-plugins-apikey`, the only Secret the job may read or patch. When the
key is missing or rejected, the job logs in as `admin` with its password,
replaces the key and stores it; a new database starts with password login
enabled.

| Plugin | Version | Adds |
| --- | --- | --- |
| `resource-map` | 0.1.0 | *Resource Map* under *Application*: workloads, Pods, Services, Ingresses and storage of a namespace as a graph |

## Metrics

Kite reads metrics from Mimir through `kite-prometheus`
(`prometheus-proxy.yaml`), an nginx that forwards only
`/prometheus/api/v1/` and adds a federated `X-Scope-OrgID` over every tenant,
because Kite cannot send headers itself. The cluster entry in the generated
config points `prometheusURL` at it.

That proxy reads every tenant without authentication, so a
`CiliumNetworkPolicy` admits only the Kite pod and it has no route outside the
cluster. Inside Kite, raw PromQL is limited to `admin`, and pod graphs follow
the pod permissions. The cluster-wide CPU and memory history on the overview
is shown to every logged-in user, as aggregates only.

Kite's node graphs filter cAdvisor series on `node`, so Alloy adds that label
to the kubelet and cAdvisor scrapes from the node name.
