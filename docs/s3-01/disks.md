# Disks

Two disks, both partitioned by `nix/hosts/s3-01/disko.nix`:

- **`xvda`, 40 GiB** — ESP (512 MiB, vfat) plus ext4 root.
- **`xvdb`, 100 GiB** — one XFS partition at `/var/lib/seaweedfs`, `noatime`.

That mount holds everything SeaweedFS keeps: volume data, the master meta
folder, and the filer's embedded leveldb2 metadata store inside it. XFS is
carried over from the Garage deployment that preceded it, where upstream
advised XFS for the data directory and against ext4 because its stricter inode
limits bite once many objects are stored. That reasoning is not Garage-specific
and nothing about SeaweedFS argues for changing it. Nothing here relies on
filesystem snapshots.

Both disks sit on the same SSD storage repository (`vhost1-ssd2`), so there is
no SSD/HDD tier to split metadata from data. Filesystems mount by partlabel, not
device node.

`xvdb` is declared in `disko.nix`, so **a reinstall repartitions it and destroys
every stored object.** Ordinary applies leave it alone. The partition that used
to be mounted at `/var/lib/garage` was reformatted for this mountpoint rather
than migrated — see [SeaweedFS](seaweedfs.md).
