# Service PCs

`gewis.servicePc` is the shared configuration for all service PCs.

It gives a machine:

- a real GNOME desktop, logged in by itself at boot;
- browsers, each pointed at a fixed URL, and any other applications the host
  names;
- each of those pinned to a workspace or screen;
- an NFC reader that types scanned tags into whatever has focus;
- remote control of the session;
- a boot splash showing the wallpaper instead of kernel output;
- a power-off every evening, so a stuck session never outlives the day.

The module is defined in `nix/modules/service-pc/` and imported by every
host through `nix/modules/default.nix`, so it is available everywhere and does
nothing until a host sets `gewis.servicePc.enable`. The hosts pair it with
`gewis.tmpfsRoot` for the disk layout and `gewis.admin` for the `cbc` account;
[Installing](install.md) walks through a new one.

| Host | What it shows |
| --- | --- |
| [`pcgewisc`](../pcgewisc/index.md) | SudoSOS POS, and Spotify on a second workspace |
| [`pcgewisd`](../pcgewisd/index.md) | SudoSOS POS |
| [`pcgewisinfo`](../pcgewisinfo/index.md) | One page fullscreen, from a secret URL |

## The module names no applications

The module knows about "a set of browsers" and "a set of extra apps". It does
not know which URLs or which apps. Everything machine-specific, which packages, which URL, any
unfree licence, belongs in `nix/hosts/<host>/`, so a second service PC running
something else is a new host file and not a change here.
