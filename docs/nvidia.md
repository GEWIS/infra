# NVIDIA driver

`gewis.nvidia` runs NVIDIA's driver with the open kernel modules
(`hardware.nvidia.open`) instead of `nouveau`. It is defined in
`nix/modules/nvidia.nix`, imported by every host through
`nix/modules/default.nix`, and does nothing until a host sets
`gewis.nvidia.enable = true`.

On `nouveau`, some Aurora pages flickered in Firefox. The open modules
blacklist `nouveau`. They only support Turing (GTX 16xx, RTX 20xx) and newer.
An older card needs `hardware.nvidia.open = false`, and this module does not
set that. `nvidia-x11` is allow-listed as the only unfree package, and
`nvidia-settings` is left out.

## Checking a host

Find the card, then check which driver is bound to it after a switch:

```sh
lspci -nnk | grep -A3 -E 'VGA|3D|Display'   # "Kernel driver in use: nvidia"
nvidia-smi                                  # lists the card and the driver version
```
