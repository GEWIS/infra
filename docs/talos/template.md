# The template is a manual prerequisite

The provider can clone a template but cannot build one — `template` is
`Required` and forces replacement, and there is no way to attach an uploaded
disk as a VM's boot disk. So the Talos image becomes a template **by hand,
once**. Talos upgrades afterwards go through `talosctl upgrade`, never a
re-import.

The template is the **nocloud** disk image: Talos baked onto the disk, so a
clone boots straight from its own disk with no ISO and no runtime dependency on
any ISO SR. Given no config source it lands in maintenance mode on its reserved
address, waiting for tofu to push the machine configuration over the API.

The image is built at [Image Factory](https://factory.talos.dev) with a
schematic carrying three extensions:

| Extension | Why |
| --- | --- |
| `siderolabs/xen-guest-agent` | reports guest IPs to Xen Orchestra |
| `siderolabs/iscsi-tools` | Longhorn needs `iscsiadm`, or volumes never attach |
| `siderolabs/util-linux-tools` | Longhorn needs `fstrim` |

The schematic id is
`58eedd04d458e2c900727f5a3af74a3ef6453b9902b23decb590c0007388187a` — a content
hash of exactly those three, verified against the Factory. It is pinned in
`main.tf` as the `schematic_id` local, which drives both the nocloud template
image and the `installer` reference in `machine.install.image`.

## The disk-scramble bug, and why the template carries an empty CD drive

The template ships with **one bootable disk plus an empty CD drive**, mirroring
the shape of the working `s3-01` Ubuntu template. The empty CD is not cosmetic —
it is the fix for a provider bug.

`terra-farm/xenorchestra` v0.40.0 **scrambles the two `disk` blocks when cloning
a template that has no CD drive**: both disks come out at the second block's size
both at the wrong size, silently losing the sized system disk, sometimes with
non-deterministic device names too. A CD drive present on the template makes disk
sizing correct. Proven again this session — the nocloud template with an empty CD
cloned to correct root and data sizes on all three nodes, across hosts.
`s3-01`, which has always sized correctly, happens to carry exactly this shape:
OS on the disk plus an empty CD drive.

An **empty** CD is chosen deliberately because it needs no ISO and no ISO SR at
runtime: its boot order is irrelevant, because an empty drive has nothing to
boot, so UEFI/OVMF falls through to the disk. (`s3-01` boots CD-first, `dcn`, and
still comes up off its disk for exactly this reason.)

This is why the earlier **diskless template + bootable metal-ISO** approach was
abandoned. The provider has no boot-order attribute (confirmed for every released
version) and no CD-eject. With a blank disk and a bootable Talos metal ISO in a
CD-first VM, OVMF boots the ISO on every reboot: the node installs to `/dev/xvda`,
reboots, and lands straight back in the ISO — a maintenance-mode loop where
bootstrap never completes. Escaping it would need a manual, out-of-band
`vm.setBootOrder` / `ejectCd` per node, only reachable through xo-cli's JSON-RPC
(not the REST API, not the provider). nocloud + empty CD avoids all of it, needs
zero boot-order management, and has no runtime coupling to the flaky SMB ISO SR.

## Building the template

Named `talos-1.13.8-nocloud`, UEFI (no Secure Boot). The provider cannot do any
of this, so it is done once by hand with the XO REST API and `xo-cli`.

1. Download the nocloud disk image from Image Factory and decompress it:

   ```sh
   curl -LO "https://factory.talos.dev/image/58eedd04d458e2c900727f5a3af74a3ef6453b9902b23decb590c0007388187a/v1.13.8/nocloud-amd64.raw.xz"
   unxz nocloud-amd64.raw.xz
   ```

2. Convert the raw image to a **dynamic** VHD, which shrinks the upload from
   ~4.45 GiB raw to ~280 MiB:

   ```sh
   qemu-img convert -O vpc -o subformat=dynamic nocloud-amd64.raw talos-1.13.8-nocloud.vhd
   ```

3. Import the VHD as a VDI into a disk SR over the XO REST API (default upload
   format is VHD; pass `raw=true` only for a raw image):

   ```sh
   curl -b "authenticationToken=$XOA_TOKEN" \
     -H "Content-Type: application/octet-stream" \
     --data-binary @talos-1.13.8-nocloud.vhd \
     "https://xoa.gewis.nl/rest/v0/srs/<sr-uuid>/vdis?name_label=talos-1.13.8-nocloud-disk"
   ```

4. Build the template VM with `xo-cli` (JSON-RPC — the empty-CD trick is not
   expressible over REST). Authenticate once, then create the VM from a
   UEFI-capable base template, attach the imported disk as the boot disk, add an
   empty CD drive, and convert to a template. Note that pool templates are
   addressed by a **composite** id, `<pool-uuid>-<template-uuid>`:

   ```sh
   npx --yes xo-cli register --token "$XOA_TOKEN" https://xoa.gewis.nl
   npx --yes xo-cli vm.create name_label=talos-1.13.8-nocloud \
     template=<pool-uuid>-<GenericLinuxUEFI-uuid> hvmBootFirmware=uefi bootAfterCreate=false
   npx --yes xo-cli vm.attachDisk vm=<vm-uuid> vdi=<imported-vdi-uuid> bootable=true position=0
   # insert any ISO then eject it — leaves an empty CD drive attached (the disk-scramble fix)
   npx --yes xo-cli vm.insertCd id=<vm-uuid> cd_id=<any-iso-vdi-uuid> force=true
   npx --yes xo-cli vm.ejectCd id=<vm-uuid>
   npx --yes xo-cli vm.convertToTemplate id=<vm-uuid>
   ```

The result is a template with one bootable disk (the nocloud image) at position 0
plus one empty CD drive, UEFI — the same shape as the `s3-01` template. A full
clone resizes the system disk to the configured root size and Talos grows its EPHEMERAL partition
into the space on first boot. Rename the `template_name_label` local in `main.tf`
if you name the template something other than `talos-1.13.8-nocloud`.
