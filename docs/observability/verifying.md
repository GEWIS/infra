# Verifying

Run these in order; each one gates the next.

```sh
bao kv get garage/observability/loki
kubectl -n observability get externalsecret
```

Then that data actually lands in Garage, which is the part worth proving — Loki
on Garage is well travelled, Mimir's and Tempo's object clients less so:

```sh
aws --endpoint-url http://10.82.50.100:3900 s3 ls s3://loki
aws --endpoint-url http://10.82.50.100:3900 s3 ls s3://mimir/blocks/
```

Then tenancy, where the negative results are the interesting ones:

```sh
curl -s "http://loki.observability.svc:3100/loki/api/v1/labels"
curl -s -H 'X-Scope-OrgID: CBC' "http://loki.observability.svc:3100/loki/api/v1/labels"
curl -s -H 'X-Scope-OrgID: ABC-CRM' "http://loki.observability.svc:3100/loki/api/v1/labels"
```

The first must be refused for want of a tenant, the second must return labels,
and the third must be empty — never CBC's.

Finally through Grafana: log in with GEWISWG, land in the `CBC` org as `Editor`,
and confirm the federated datasources return logs and `up{}`. An account holding
only `GRAFANA-ABC_CRM-RO` must land in exactly one org, see only that namespace,
and have no route to the rest.
