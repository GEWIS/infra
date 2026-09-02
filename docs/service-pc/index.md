# Service PCs

`gewis.servicePc` is the shared configuration for all service PCs.

It gives a machine:

- a real GNOME desktop, logged in by itself at boot;
- a browser pointed at a fixed URL, and any other applications the host names;
- each of those pinned to a workspace or screen;
- remote control of the session.

The module is defined in `nix/modules/service-pc/` and imported by every
host through `nix/modules/default.nix`, so it is available everywhere and does
nothing until a host sets `gewis.servicePc.enable`.

## The module names no applications

The module knows about "a browser" and "a set of extra apps". It does not know
which apps. Everything machine-specific, which packages, which URL, any
unfree licence, belongs in `nix/hosts/<host>/`, so a second service PC running
something else is a new host file and not a change here.
