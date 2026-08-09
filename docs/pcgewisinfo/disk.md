# Disk and persistence

`/` is a 2 GiB tmpfs, wiped every boot. The NVMe carries an ESP plus a btrfs
partition with `/nix` and `/persist` subvolumes, both `compress=zstd,noatime`.

Everything that must survive a reboot is listed in `persistence.nix`:
`/var/lib/nixos`, `/var/lib/systemd`, `/var/lib/comin`, `/var/lib/netbird`,
`/var/log/journal`, `/etc/machine-id`, and the ssh host key pair. **A file that
is not listed there does not exist after the next boot.**

The sops age key lives at `/persist/var/lib/sops-nix/key.txt`, outside the
tmpfs, so secrets decrypt on boot.
