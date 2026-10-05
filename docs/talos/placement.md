# Placement and disks

`affinity_host` steers each VM to a physical host, but the real anchor is the
host-local SR its disks sit on: a VM cannot boot where its storage is not.

| Node | Host | SR |
| --- | --- | --- |
| talos-01 | gewisvhost1 | vhost1-ssd2 |
| talos-02 | gewisvhost3 | vhost3-ssd |
| talos-03 | gewisvhost4 | Local storage |

One node per host, so losing a host costs one etcd member and one Longhorn
replica. The pool is `vhost1`/`vhost3`/`vhost4` — there is no `vhost2`. On
`vhost4`, `vhost4-ssd` is nearly full; `Local storage` is the SR with room.

Each node gets 4 vCPU and static memory set per node in the `nodes` map:
30 GiB, except 16 GiB for talos-01 because `vhost1` has no more room until the
old cluster's `swarm201` is gone. Raising it is a static-memory change, so tofu
halts the VM; do it with `-target`, one node at a time, like a disk resize.

Two disks per node: a 50 GiB system disk (`xvda`) and a 300 GiB Longhorn data
disk (`xvdb`). **The system disk cannot be grown in
place** — Talos fixes the STATE partition boundaries at install, so resizing it
later means replacing the VM (`tofu apply -replace`), cheap for a fresh node.
The Longhorn disk is the opposite: raise `data_disk_gib` and its
`UserVolumeConfig` expands on the next boot. The provider resizes the VDI in
place but halts the VM to do it, and a plain `apply` would halt all three nodes
at once — so grow one node per apply,
`tofu apply -target='module.vm["talos-01"]'`, and wait for Longhorn to report it
healthy before the next.

Longhorn's data disk is mounted by a `UserVolumeConfig` named `longhorn`, which
forces the mount to `/var/mnt/longhorn`; Longhorn's Helm `defaultDataPath` must
match. The disk is selected by `!system_disk` rather than a device path, so Xen
attach order cannot misroute it. `machine.disks` is deprecated from Talos 1.10
on and `UserVolumeConfig` is its replacement.

The kubelet needs a bind mount for that path as well, or Longhorn cannot publish
volumes into workload pods:

```yaml
machine:
  kubelet:
    extraMounts:
      - destination: /var/mnt/longhorn
        type: bind
        source: /var/mnt/longhorn
        options: [bind, rshared, rw]
```

Size the data disk above the largest volume it must hold: Longhorn schedules a
replica only when the disk fits the whole volume, and a PVC the size of the disk does not fit
it once filesystem overhead is taken. `storageReservedPercentageForDefaultDisk: 0`
is safe here only because the disk is dedicated to Longhorn.
