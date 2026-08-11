# Placement and disks

`affinity_host` steers each VM to a physical host, but the real anchor is the
host-local SR its disks sit on: a VM cannot boot where its storage is not.

| Node | Host | SR |
| --- | --- | --- |
| talos-01 | gewisvhost1 | vhost1-ssd2 |
| talos-02 | gewisvhost1 | vhost1-ssd2 |
| talos-03 | gewisvhost3 | vhost3-ssd |

Two nodes share `vhost1` for now because `vhost4` is out of space; move a node
by changing one map entry once it frees up. The pool is `vhost1`/`vhost3`/`vhost4`
— there is no `vhost2`.

Two disks per node: a 40 GiB system disk (`xvda`) and a 150 GiB Longhorn data
disk (`xvdb`). **The system disk cannot be grown in
place** — Talos fixes the STATE partition boundaries at install, so resizing it
later means replacing the VM (`tofu apply -replace`), cheap for a fresh node.
The Longhorn disk is the opposite: grow the VDI and its `UserVolumeConfig`
expands on the next boot.

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
