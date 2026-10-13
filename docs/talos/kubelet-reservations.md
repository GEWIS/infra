# Kubelet memory reservations

[Static memory](memory.md) does not stop a node starving itself. A BestEffort
pod with no limit (the pwned-passwords redis, 8.5 GiB) filled talos-01: the
kernel spent nine minutes evicting page cache and re-reading binaries from
`xvda` before the OOM killer fired, and in that window every Talos service,
etcd, and the Longhorn iSCSI sessions timed out, leaving volumes read-only
cluster-wide.

`machine.kubelet.extraConfig` in `terraform/10_talos-hosts` therefore sets:

| Setting | Value | Talos default |
| --- | --- | --- |
| `systemReserved.memory` | 1Gi | 512Mi |
| `kubeReserved.memory` | 1Gi | unset |
| `evictionHard["memory.available"]` | 1Gi | 100Mi |

The reservations shrink the `kubepods` cgroup, so a runaway pod hits a cgroup
OOM while the host keeps 2 GiB for etcd, containerd and machined. The eviction
threshold lets kubelet evict before that. `evictionHard` replaces the whole
default map, so the disk thresholds are restated next to it.

A kubelet change applies in `auto` mode without a reboot, but
`talos_machine_configuration_apply` depends on `module.vm`, so
`-target='talos_machine_configuration_apply.this["talos-01"]'` still plans
every VM. Any drift between the `nodes` map and XO (vCPUs, memory) then halts
VMs in the same run. Read the targeted `tofu plan` and apply only when it shows
no `module.vm` changes.
