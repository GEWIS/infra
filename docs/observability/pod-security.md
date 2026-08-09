# Pod Security, and why one namespace is privileged

Talos enforces the baseline standard, which forbids hostPath volumes. Exactly one
workload here needs them — the node exporter, reading `/proc` and `/sys` — so it
gets its own namespace, `node-exporter`, labelled
`pod-security.kubernetes.io/enforce: privileged`, in the same spirit as `dns` and
`traefik`.

`observability` itself carries **no PSA label** and stays baseline. Labelling the
whole stack privileged to satisfy one DaemonSet would drop enforcement for Loki,
Mimir, Tempo and Grafana as well. Alloy needs no host access at all: pod logs come
from the API server, kubelet and cadvisor over HTTPS, everything else over the pod
network.
