# Touchscreens and workspaces

## The panel

`touch.enable` says the host is a touchscreen with no keyboard or mouse. It
turns on GNOME's on-screen keyboard and reclassifies the panel for libinput:
the panels in use announce themselves as tablets, which libinput would treat as
a pen device, so a udev rule matching `touch.vendorId` and `touch.productId`
marks the device as a touchscreen instead. A different panel needs its two IDs
from `lsusb`.

## The on-screen keyboard

`touch.enable` also turns on GNOME's keyboard and ships a small shell
extension, `osk-on-focus`, that opens it whenever an application focuses a text
field. Applications announce focused fields to mutter over the Wayland
text-input protocol. GTK only speaks that protocol when `GTK_IM_MODULE` is
unset, so every service PC runs IBus with its Wayland frontend, which leaves
the variable out of the session. Mutter itself raises the keyboard only when a
field that already has focus is enabled a second time, which GTK does on a tap
into a focused entry and Firefox never does; the extension raises it on every
focus-in instead, so a field focused by a tap or by the page itself gets the
keyboard straight away. The keyboard closes when the field loses focus, and a
keyboard the user dismissed stays hidden until focus leaves and returns.

Firefox announces a field each time focus moves from a non-editable element to
an editable one. Focus moving straight between two fields, or set from
JavaScript while another field is active, does not count, so a web app that
wants the keyboard back must blur the active element before focusing the next.

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
maximised onto the workspace it lands on. See
[Placement](options.md#placement) for how the two options interact.

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
