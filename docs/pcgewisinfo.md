# pcgewisinfo

The info-screen kiosk. It also serves DHCP and printing for the small LAN behind
it. Installed by hand; updated automatically by comin.

## Updates

`nix/hosts/pcgewisinfo/comin.nix` points comin at
`https://github.com/GEWIS/nixos-config.git`, branch `main`. comin polls that
repo and switches the host, so **pushing to `main` deploys** — including commits
that only touch `s3-01`. A configuration that fails to evaluate simply stops
updates; the running system is untouched.

There is no `nixos-rebuild --target-host` path here: root has no ssh access
(`PermitRootLogin = "no"`).

## Kiosk

`services.cage` runs Firefox fullscreen on tty1 as the unprivileged `gewis`
user. The launcher reads the target URL from the `kioskUrl` sops secret and
polls it with curl until it answers before starting the browser, so a slow or
briefly-down backend shows nothing rather than an error page. Firefox runs on
Wayland from a fresh throwaway profile each start.

The unit restarts on failure, up to 10 times in 60 seconds.

`autovt@tty1` is disabled. The `services.cage` module only sets
`Conflicts=getty@tty1.service` and `restartIfChanged = false`, so a
`nixos-rebuild switch` reactivates the getty on tty1, whose conflict stops the
running compositor — and cage is never restarted (`X-RestartIfChanged=false`,
and `Restart=on-failure` does not fire on a job-driven stop). Freeing the VT the
way the upstream `greetd` module does keeps cage on tty1 across a switch; the
session survives untouched until the next reboot.

Mice are hidden rather than disabled: a udev rule sets `LIBINPUT_IGNORE_DEVICE`
on every `ID_INPUT_MOUSE` device, which removes the pointer without a
compositor-level hack. Sleep, suspend, hibernate and hybrid-sleep targets are
disabled so the screen never blanks itself off.

`systemd.timers.daily-poweroff` powers the machine down at 23:00. Nothing turns
it back on — that is wake-on-schedule in firmware, or a human.

## Accounts

| User | Purpose |
| --- | --- |
| `gewis` | uid 1000, no password, runs the kiosk session |
| `cbc` | Administrator, in `wheel`, password from the `cbcPassword` secret |

`wheelNeedsPassword` is off, and `users.allowNoPasswordLogin` is on because
`gewis` deliberately has an empty password.

sshd allows password authentication for `cbc` and refuses root outright. It is
**not** opened globally: `openFirewall = false`, and port 22 is allowed only on
the LAN interface.

## Network

| Interface | Role |
| --- | --- |
| `enp0s31f6` | Uplink, DHCP client |
| `enp1s0` | Booth LAN, static `10.0.0.1/24` |

dnsmasq serves DHCP on `enp1s0` only (`bind-interfaces`, with the uplink
explicitly excluded), handing out `10.0.0.100–200`. The two printers hold
infinite static leases by MAC: `10.0.0.10` and `10.0.0.11`.

On the LAN interface the firewall opens 53/udp, 67/udp, 53/tcp and 22/tcp.

## Printing

CUPS with two PPDs vendored in `assets/`, both reached over IPP:

| Printer | Address |
| --- | --- |
| `PSGEWIS1` (default) | `10.0.0.10` |
| `PSGEWIS3` | `10.0.0.11` |

[GEPRINT](https://github.com/GEWIS/GEPRINT) listens on 8080. Its own
`openFirewall` is off; `printers.nix` instead opens 8080 **only on the NetBird
interface**, so it is reachable from the mesh and not from the booth LAN or the
uplink. The interface name is read from the NetBird client rather than written
out, so it cannot drift.

## NetBird

The client attribute is `netbird`, not the `gewis` default used by `s3-01`. That
name determines the systemd unit, the `nb-netbird` interface and the
`/var/lib/netbird` state directory, so changing it would make the host register
as a **new peer** and lose its mesh address. It is pinned for that reason.

## Disk and persistence

`/` is a 2 GiB tmpfs, wiped every boot. The NVMe carries an ESP plus a btrfs
partition with `/nix` and `/persist` subvolumes, both `compress=zstd,noatime`.

Everything that must survive a reboot is listed in `persistence.nix`:
`/var/lib/nixos`, `/var/lib/systemd`, `/var/lib/comin`, `/var/lib/netbird`,
`/var/log/journal`, `/etc/machine-id`, and the ssh host key pair. **A file that
is not listed there does not exist after the next boot.**

The sops age key lives at `/persist/var/lib/sops-nix/key.txt`, outside the
tmpfs, so secrets decrypt on boot.

## Secrets

`secrets/pcgewisinfo.yaml`, encrypted to the host key only, so it can currently
be read and edited only from the host itself.

That is a gap rather than a decision. Adding an admin as a recipient needs the
host's key, because `sops updatekeys` decrypts before it re-encrypts. From the
host, with `/persist/var/lib/sops-nix/key.txt` available:

```sh
SOPS_AGE_KEY_FILE=/persist/var/lib/sops-nix/key.txt \
  sops updatekeys secrets/pcgewisinfo.yaml
```

Add `admin_luuk` back to this file's rule in `.sops.yaml` first, or the re-key
is a no-op.

| Secret | Use |
| --- | --- |
| `kioskUrl` | Page the kiosk opens; owned by `gewis` |
| `cbcPassword` | Hashed password for `cbc`; `neededForUsers` |

## Fonts

`corefonts` and `vista-fonts` are unfree and allow-listed individually, on top
of Noto (including CJK and colour emoji), Liberation, DejaVu, Ubuntu and Font
Awesome — the kiosk page needs Consolas and the usual Microsoft metric
equivalents to render as designed.
