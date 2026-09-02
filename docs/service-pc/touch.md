# Touchscreens and workspaces

## Workspaces

`workspaces` fixes how many workspaces the session has, and switches GNOME off
dynamic workspaces to do it. That matters: with dynamic workspaces GNOME adds
and removes them as windows come and go, so "workspace 2" would not mean
anything stable and an app could not be assigned to it.

Each application then names where it belongs:

```nix
browser.workspace = 1;
apps.spotify.workspace = 2;
```

Placement happens once, when the window first appears, and the window is
maximised onto the workspace it lands on, see
[Options](options.md#when-a-window-does-not-move) for what to do when a window
stays put.

## More than one screen

Set `multiMonitor = true` and give an application a `monitor` instead of a
`workspace`:

```nix
multiMonitor = true;
apps.spotify.monitor = 2;
```

The window is moved to that monitor and maximised there, and stays visible
whichever workspace the primary screen is showing, GNOME's
`workspaces-only-on-primary` default does that for us.

Monitor numbering follows GNOME's own logical monitor order, which the module
reads at runtime from mutter. Nothing here declares resolutions or arrangement:
GNOME detects the layout, and the module only places windows by index.

!!! warning "Remote viewing only shows the primary monitor"
    `gnome-remote-desktop` mirrors the primary monitor or creates a virtual
    one; there is no multi-monitor passthrough. Whatever is on monitor 2 is
    invisible to a remote client.
