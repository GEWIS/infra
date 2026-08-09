# How it fits together

OpenTofu never talks to XCP-ng directly. It talks to **Xen Orchestra's
websocket API** through the
[`terra-farm/xenorchestra`](https://registry.terraform.io/providers/terra-farm/xenorchestra/latest)
provider, so a reachable Xen Orchestra with an API token is a prerequisite.

Two modules, split by concern:

| Module | Responsibility |
| --- | --- |
| `terraform/modules/xcpng-vm` | Clones the template, attaches disks and NIC, renders cloud-init. Knows nothing about NixOS. Outputs `vm_id` and `vm_ipv4`. |
| `terraform/modules/nixos-host` | Runs nixos-anywhere against an already-reachable address. Knows nothing about XCP-ng. |

`terraform/s3-01/main.tf` wires them over a `locals.hosts` map with `for_each`, so
adding a host is one more map entry. **Each map key must equal the
`nixosConfigurations` name** — the flake attributes are derived from it.
`nixos-host` takes the VM's `vm_id` as `instance_id`, so replacing the VM forces
a full reinstall while ordinary applies only rebuild.
