# Dashboards are owned by tofu, in the CBC org

`terraform/grafana-config/dashboards.tf` imports every dashboard into the CBC
organization, for the reasons in [Grafana orgs](grafana-orgs.md). Two maps, split
by whether the JSON hardcodes a datasource:

| Map | Source | Datasource |
| --- | --- | --- |
| `dashboards` | grafana.com `{id, revision}` | left as the export has it |
| `dashboards_pinned_datasource` | a `url`, on grafana.com or raw | placeholder replaced with the CBC Mimir uid |

An export that names its datasource with a literal placeholder —
`${DS_PROMETHEUS}`, `${DS_PROMXY}` — has no chance of resolving on import, so
tofu substitutes the uid for it. That map takes a `url` rather than an id because
not every dashboard is published on grafana.com.

The provider deletes `id` and `version` from the JSON before posting, so a raw
export carrying `"id": 1` imports cleanly and needs no editing. `uid` is kept,
which is what makes an import idempotent.

## Cilium's dashboard ships with Cilium

`cilium-dashboard.json` is a file in the Cilium chart
(`install/kubernetes/cilium/files/cilium-agent/dashboards/`), not a grafana.com
entry, so it is fetched raw at a tag. A Renovate `customManager` in
`renovate.json` matches `cilium/cilium/v…` in `dashboards.tf` and bumps it
against GitHub releases. It is a **separate PR** from the chart version in
`terraform/talos-bootstrap`, so land the two together or the dashboard drifts
from the agent that serves the metrics.

The other dashboards in that directory are not imported:

- **`cilium-operator-dashboard.json` is an AWS dashboard.** Nine of its eleven
  series are `cilium_operator_ec2_*` and `cilium_operator_ipam_*`, which exist
  only under ENI IPAM; with `ipam.mode=kubernetes` all that would render is CPU
  and resident memory, and `cilium_operator_ipam_ips` does not exist in Cilium
  1.20 at all.
- **Hubble's four dashboards** need `hubble.metrics.enabled`, which is unset, so
  every panel would be empty. Hubble itself runs — see [Hubble](hubble.md).

One panel on the agent dashboard stays empty by design:
`cilium_bpf_syscall_duration_seconds` is disabled in Cilium's default metric set.
Turning it on means `prometheus.metrics = ["+cilium_bpf_syscall_duration_seconds"]`
in the Cilium values, and it is a histogram per syscall operation — the reason it
is off by default.

## Cilium's metrics have two switches

`operator.prometheus.enabled` defaults **true** (port 9963); the agent's
`prometheus.enabled` defaults **false** (port 9962) and is set explicitly in the
Cilium values. Either one, when enabled, annotates its pod with
`prometheus.io/scrape` and `prometheus.io/port` and declares a matching
`containerPort` — which is precisely what alloy-metrics' `annotated_pods` job
keys on, so neither needs a ServiceMonitor or a scrape block of its own. See
[Collection](collection.md).

The agent's metrics port comes with a **hostPort 9962** on every node, so it is
reachable from the campus LAN like the other hostPort workloads.
