# Installing a service PC

A service PC is installed once, by hand, with `nixos-anywhere` from the dev
shell. After that comin keeps it on `main`. The order matters: the host's
secrets have to exist before the first boot, because the `cbc` password and
the browser URL are read from them during activation.

## 1. An age key for the host

Generate the key on your own machine and keep the private half out of git:

```sh
age-keygen -o pcgewisx-age.key
```

Put the public key under `hosts` in `nix/recipients.nix`, regenerate
`.sops.yaml` and create the host's secrets file:

```sh
nix run .#sops-config
sops secrets/pcgewisx.yaml
```

It needs at least `cbcPassword` (a hash from `mkpasswd -m yescrypt`),
`rdpPassword`, `netbird-setupkey` (a reusable setup key from the NetBird
dashboard) and the URL the browser opens.

## 2. The host configuration

Create `nix/hosts/pcgewisx/default.nix` after the pattern of `pcgewisd`:
`gewis.tmpfsRoot`, `gewis.admin`, `gewis.comin`, `gewis.netbird`,
`gewis.zabbixAgent` and `gewis.servicePc` with whatever the machine shows.
Add it to `nixosConfigurations` in `flake.nix`, write its page under `docs/`
and list that in `mkdocs.yml`. Set `gewis.tmpfsRoot.device` if the disk is not
`/dev/nvme0n1`.

`git add` everything, then check it evaluates:

```sh
nix build .#nixosConfigurations.pcgewisx.config.system.build.toplevel
```

## 3. The install

Boot the machine from a NixOS installer image, connect it to the network and
set a root password in the installer so ssh works. Then, from your machine,
with the age key laid out where sops-nix expects it on the target:

```sh
mkdir -p extra/persist/var/lib/sops-nix
install -m 0600 pcgewisx-age.key extra/persist/var/lib/sops-nix/key.txt
nixos-anywhere --flake .#pcgewisx --extra-files extra root@<installer-ip>
```

`nixos-anywhere` partitions the disk with the layout from `gewis.tmpfsRoot`,
installs the system and copies `extra/` onto the new root, so the key lands on
the `/persist` subvolume and every secret decrypts on the first boot.

## 4. After the first boot

- `journalctl -u comin` shows the host following `main`.
- `nixos-generate-config --show-hardware-config --no-filesystems` lists the
  kernel modules and firmware the machine wants. Put what matters in a
  `boot.nix` next to the host file, the way `pcgewisinfo` does, so the GPU and
  network card get their firmware.
- The host appears in the NetBird dashboard under its `dnsLabel`; register it
  in Zabbix under its hostname. Both are reachable over the mesh only.
- Log in over ssh as `cbc` from the mesh to confirm the password secret was
  applied.
