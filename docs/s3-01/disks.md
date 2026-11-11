# Disks

Two disks, both partitioned by `nix/hosts/s3-01/disko.nix`:

- **`xvda`, 40 GiB** — ESP (512 MiB, vfat) plus ext4 root.
- **`xvdb`, 1000 GiB** — one XFS partition at `/var/lib/seaweedfs`, `noatime`.

That mount holds everything SeaweedFS keeps: volume data, the master meta
folder, and the filer's embedded leveldb2 metadata store inside it. XFS is
carried over from the Garage deployment that preceded it, where upstream
advised XFS for the data directory and against ext4 because its stricter inode
limits bite once many objects are stored. That reasoning is not Garage-specific
and nothing about SeaweedFS argues for changing it. Nothing here relies on
filesystem snapshots.

Both disks sit on the same SSD storage repository (`vhost3-ssd`), so there is
no SSD/HDD tier to split metadata from data. Filesystems mount by partlabel, not
device node.

**Growing `xvdb`** starts in code: raise `data_disk_gib` in
`terraform/10_s3-01/main.tf` and apply. The provider grows the VDI in place but
halts the VM to do it, so SeaweedFS is down for that apply. Then grow the
partition and the filesystem on the host, online:

```sh
nix-shell -p cloud-utils --run 'growpart /dev/xvdb 1'
xfs_growfs /var/lib/seaweedfs
```

Resizing in Xen Orchestra by hand leaves the code behind, and the next apply
then tries to shrink the disk back, which XCP-ng cannot do.

`xvdb` is declared in `disko.nix`, so **a reinstall repartitions it and destroys
every stored object.** Ordinary applies leave it alone. The partition that used
to be mounted at `/var/lib/garage` was reformatted for this mountpoint rather
than migrated — see [SeaweedFS](seaweedfs.md).
