# The config

zot's config is YAML under `values.config` of the HelmRelease `zot-values` in
`flux/50_apps/zot/config.yaml`. That release installs the local chart
`charts/zot-values` with three values fragments:

| Fragment | From |
| --- | --- |
| `publishers` | the ConfigMap `zot-publishers`, see [Publishing](publishing.md) |
| `apps` | the ConfigMap `zot-app-access`, which the `zot-app-access` release renders from the [app access](../cluster/app-access.md) list |
| `lanReader.password` | the Secret `zot-lan-reader`, see [LAN login](lan-login.md) |

It renders the ConfigMap `zot-values`, the values of the `zot` HelmRelease,
which are `config` plus the generated policies, along with the htpasswd Secret
`zot-htpasswd` and the Middleware `zot-lan-reader`. The `zot` HelmRelease reads
`zot-values` through `valuesFrom` and `dependsOn: zot-values`. The zot chart
turns `config` into the Secret `zot-config`, mounted as `/etc/zot/config.json`,
and restarts the pod when it changes.

zot applies only the longest matching repository pattern. The template,
`charts/zot-values/templates/zot-values.yaml`, gives each app's group
`<app>/**`, and every published path an entry of its own: the group policy of
the app its first segment names, if any, then one policy per publisher, with
conditions on the token's claims (`req.claims`).

All three fragments are whole values files under the key `values.yaml` and
carry `reconcile.fluxcd.io/watch: Enabled`, so an edit upgrades `zot-values` at
once, and the new values upgrade `zot`.

## Refused entries

The template fails on:

- a publisher whose `repository` is not lowercase `gewis/<repo>`, whose
  `workflow` is not a bare `.yml`/`.yaml` file name, whose `environment` has
  characters other than letters, digits, `.`, `_` and `-`, or whose `paths` is
  empty;
- a path that is not a lowercase image path, or that `<app>/**` would shadow;
- an app whose `name` is not a lowercase path segment or whose `group` is empty.

The `zot-values` upgrade then fails with the entry in its message, the
`zot-values` ConfigMap keeps the last good values, and zot keeps running on
them.
