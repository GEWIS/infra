# What is actually deployed

Two Deployments — `authentik-server` and `authentik-worker` — and nothing else.

**There is no Redis.** authentik 2026.x moved its cache, channel layer and task
queue into Postgres (`django_postgres_cache`, `django_channels_postgres`,
`django-dramatiq-postgres`), and the chart dropped the dependency with them:

```console
$ yq '.entries.authentik | sort_by(.created) | .[-1] | .dependencies' index.yaml
- {name: postgresql, condition: postgresql.enabled}    # off by default
- {name: authentik-remote-cluster, alias: serviceAccount}
```

Every guide written before that release provisions a Redis. Do not. Postgres is
the only dependency, which is why the database had to land first.

The bundled Bitnami `postgresql` subchart stays disabled; the database is the
shared CloudNativePG cluster, wired up as
[any other consumer](../databases/postgres.md).

## Configuration arrives as two envFrom entries

The chart flattens its `authentik.*` values into `AUTHENTIK_A__B` environment
variables inside a Secret it mounts with `envFrom`. Anything in `global.envFrom`
is appended *after* that, and for duplicate keys the last source wins — so
naming the External Secret's keys after the environment variables lets the whole
database configuration arrive without being restated in the values:

| Secret | Source | Carries |
| --- | --- | --- |
| `authentik-db` | ExternalSecret ← OpenBao | `AUTHENTIK_POSTGRESQL__{HOST,PORT,NAME,USER,PASSWORD}` |
| `authentik-auth` | SealedSecret | `AUTHENTIK_SECRET_KEY`, the bootstrap password, token and email |

The chart's own Secret still contains its default `AUTHENTIK_POSTGRESQL__HOST` of
`authentik-postgresql`. It is overridden and never used; the chart omits keys
whose value is empty, which is why no password appears there.

## The bootstrap secret is read exactly once

`AUTHENTIK_BOOTSTRAP_PASSWORD`, `_TOKEN` and `_EMAIL` are consumed on the very
first startup and ignored on every one after. The token becomes a long-lived API
token owned by `akadmin`, and that is what `terraform/authentik-config` will
authenticate with — read back out of the cluster, the way `grafana-config` reads
`grafana-auth`, so the value exists in exactly one place.

Neither value is printed anywhere. Retrieve the admin password when you need it:

```sh
kubectl -n authentik get secret authentik-auth \
  -o jsonpath='{.data.AUTHENTIK_BOOTSTRAP_PASSWORD}' | base64 -d
```

Rotating the token later means creating an `authentik_token` for a dedicated
service account and deleting `akadmin`'s. Re-sealing the bootstrap value achieves
nothing on a running instance.

## Startup order sorts itself out

The server runs the migrations; the worker's `ak healthcheck` fails until the
schema exists, so on a first install the worker restarts a few times while the
server catches up. Its startup probe allows sixty failures at ten-second
intervals, which is ten minutes of headroom — far more than the migrations take.
It is noise, not a fault.
