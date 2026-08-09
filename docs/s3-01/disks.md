# Disks

Two disks, both partitioned by `nix/hosts/s3-01/disko.nix`:

- **`xvda`, 40 GiB** — ESP (512 MiB, vfat) plus ext4 root.
- **`xvdb`, 100 GiB** — one XFS partition at `/var/lib/garage`.

XFS is deliberate: Garage's docs recommend it for the data directory and advise
**against** ext4, whose stricter inode limits bite once many objects are stored.
Garage checksums its own blocks, so a CoW filesystem buys nothing. Its LMDB
*metadata* is the fragile part, but upstream considers
`metadata_auto_snapshot_interval` a better safeguard than filesystem snapshots.

Both disks sit on the same SSD storage repository (`vhost1-ssd2`), so there is
no SSD/HDD tier to split metadata from data. Filesystems mount by partlabel, not
device node.

`xvdb` is declared in `disko.nix`, so **a reinstall repartitions it and destroys
any Garage data.** Ordinary applies leave it alone.
