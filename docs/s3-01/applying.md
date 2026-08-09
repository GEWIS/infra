# Applying

```sh
cd terraform
tofu init
tofu plan
tofu apply
```

Cloud-init installs `xe-guest-utilities`, sets `net.ifnames=0` and reboots so
the agent can report. tofu waits for an address inside `expected_ip_cidr`, then
nixos-anywhere connects over ssh, kexecs, partitions per `disko.nix`, pushes the
locally-built closure and reboots into NixOS. Create takes about 3 minutes, with
the address reaching XO roughly 120s in. The host then joins the NetBird mesh.

Subsequent applies only run `nixos-rebuild --switch`. To force a full reinstall
— rare, usually only after touching `disko.nix` or cloud-init — replace the VM:

```sh
tofu apply -replace='module.vm["s3-01"].xenorchestra_vm.this'
```
