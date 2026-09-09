# Disk and persistence

`gewis.tmpfsRoot` lays the disk out: `/` is a 2 GiB tmpfs, wiped every boot,
and the NVMe carries an ESP plus a btrfs partition with `/nix` and `/persist`
subvolumes, both `compress=zstd,noatime`.

What survives a reboot is whatever the enabled modules put on `/persist`:

| Path | Kept by |
| --- | --- |
| `/var/lib/nixos`, `/var/lib/systemd`, `/var/log/journal`, `/etc/machine-id` | `gewis.persistence` |
| `/var/lib/comin` | `gewis.comin` |
| `/var/lib/netbird` | `gewis.netbird` |
| `/var/lib/service-pc` | `gewis.servicePc.remote`, the RDP certificate |
| `/etc/ssh/ssh_host_ed25519_key` and its `.pub` | `gewis.admin` |

**A file that is not on that list does not exist after the next boot.** A host
adds its own through `gewis.persistence.extraDirectories` and `extraFiles`.

The sops age key lives at `/persist/var/lib/sops-nix/key.txt`, outside the
tmpfs, so secrets decrypt on boot.
