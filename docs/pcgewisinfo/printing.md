# Printing

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
