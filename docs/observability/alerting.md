# Alerting

Mimir evaluates the rules and sends the alerts: its ruler queries the metrics
every minute, and its built-in Alertmanager groups, routes and delivers what
fires. Grafana is not involved, so the rules are plain Prometheus rule files and
work unchanged on anything Prometheus-compatible.

| Piece | File | Mimir flags |
| --- | --- | --- |
| Rules | `flux/50_apps/observability/mimir/rules.yaml` | `-ruler-storage.backend=local`, `-ruler-storage.local.directory=/etc/mimir/rules` |
| Routing and receivers | `flux/50_apps/observability/mimir/alertmanager.yaml` | `-target=all,alertmanager`, `-alertmanager-storage.backend=local`, `-alertmanager-storage.local.path=/etc/mimir/alertmanager` |

Both are ConfigMaps mounted read-only, and Mimir re-reads them on its own poll,
so a change lands without a restart. The local backends cannot be written
through the API, which keeps git the only source.

## Rules belong to a tenant

The ruler evaluates each tenant's rules against that tenant's metrics only. The
local store reads `<directory>/<tenant>/<file>.yaml`, so the `CBC` rules
ConfigMap is mounted at `/etc/mimir/rules/CBC`. A rule under any other directory
name queries a tenant that holds none of these metrics and silently never fires.
Postgres, like everything outside the ABC namespaces, is ingested as `CBC` (see
[Tenancy](tenancy.md)). Rules for another tenant need their own ConfigMap and
mount.

Alertmanager is per tenant too: `CBC.yaml` is the configuration for tenant
`CBC`, the file name being the tenant ID.

## Routing by channel

A rule's `channel` label decides whether it notifies, and where. Each value has
its own route and receiver:

```yaml
routes:
  - matchers: ['channel="infra"']
    receiver: infra
  - matchers: ['channel="backup"']
    receiver: backup
```

A rule without a `channel` lands in `silent`: it still fires and shows in Mimir
and Grafana, but never notifies. That keeps notifications to the few rules that
need someone now; promoting a rule is adding the label.

Every receiver is empty today, so nothing notifies yet. Mattermost incoming
webhooks accept Slack's format, so a channel becomes `slack_configs` with the
webhook URL. To keep that URL out of git, the Alertmanager configuration then
moves from this ConfigMap to a Secret rendered by an `ExternalSecret` template
from OpenBao, mounted at the same path.

## The Postgres rules

| Alert | Channel | Fires when |
| --- | --- | --- |
| `PostgresBackupTooOld` | `backup` | no successful base backup for 26 hours |
| `PostgresBackupFailed` | `backup` | the latest base backup attempt failed |
| `PostgresBackupMetricsMissing` | `backup` | the Barman metrics are absent, which would keep the age alert from ever firing |
| `LastFailedArchiveTime` | `backup` | the primary's latest WAL archive attempt failed |
| `PostgresInstanceDown` | `infra` | an instance reports Postgres down |
| `PostgresMetricsMissing` | `infra` | no instance in `postgres` reports metrics at all |
| CloudNativePG defaults | — | long transactions, waiting backends, XID age, replication lag, deadlocks, a failing replica |

The `cnpg-default` group is CloudNativePG's recommended rule set from its 1.30
sample `prometheusrule.yaml`, minus its archiving rule, which moved to `backup`.
The backup metrics come from the Barman Cloud plugin
(`barman_cloud_cloudnative_pg_io_*`); WAL archiving uses CloudNativePG's own
`cnpg_pg_stat_archiver_*`, since the plugin exports nothing for it. See
[Backups](../databases/backups.md).

## Seeing alerts in Grafana

Mimir's ruler and Alertmanager APIs serve one tenant per request; a federated
`X-Scope-OrgID` such as CBC's `ABC-CRM|…|CBC` gets *"no valid org id found"*. The
CBC org therefore has two datasources pinned to `CBC` alone, defined in
`terraform/60_grafana-config/main.tf`:

| Datasource | Shows |
| --- | --- |
| `Mimir (CBC only, alerting)` | the rule groups and their state |
| `Mimir Alertmanager (CBC)` | firing alerts and silences |

The federated `Mimir` datasource has `manageAlerts` off, so Grafana does not try
the ruler through it. Queries and dashboards keep using the federated one.

Every Loki datasource has `manageAlerts` off as well. No Loki rules exist, and
the federated CBC one would fail on the ruler API the same way.
