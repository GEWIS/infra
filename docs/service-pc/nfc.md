# NFC reader

`nfcReader.enable` runs a background service that watches a USB NFC reader and
types each scanned tag's ID into whatever window has focus, as `nfc<hex-id>`
followed by Enter. It exists for the touchscreens: `pcgewisc` and `pcgewisd`
have no keyboard or mouse, so a member's NFC card is how they identify
themselves at SudoSOS, on workspace 1.

```nix
gewis.servicePc.nfcReader.enable = true;
```

## Device access

The reader is opened directly over USB (`nfcpy`'s `usb:` backend), not through
a kernel driver, so the session user needs permission on the raw USB device
node. The module tags it `uaccess` rather than handing out a static udev
group:

```
SUBSYSTEM=="usb", ATTRS{idVendor}=="072f", ATTRS{idProduct}=="2200", TAG+="uaccess"
```

`uaccess` grants the device to whoever is logged in at the seat, which on a
service PC is always the one auto-login session user. That is one line
instead of a group plus `extraGroups`, and it does not go stale if `user` is
ever renamed.

## The kernel's own NFC driver gets there first

The reader used here (an ACS ACR122U, `072f:2200`) matches the in-kernel
`pn533_usb` driver's device table, so Linux binds it automatically on plug-in
for its own NFC subsystem. `nfcpy` opens the device through `libusb` instead,
and a kernel driver already holding the interface makes that claim fail with
`Errno 16: Device or resource busy` — every single time, immediately, not
intermittently. The module blacklists `pn533_usb` so it never binds:

```nix
boot.blacklistedKernelModules = [ "pn533_usb" ];
```

This showed up as the service logging nothing but a `Device or resource busy`
retry loop forever, with `lsof` on the device node showing only the service's
own PID and nothing else — the claimant is a kernel module, not a process, so
neither `lsof` nor `ps` will ever show it directly; `lsmod | grep pn533` is
what actually reveals it.

## Typing needs a real X11 connection, even on Wayland

The service types using `pyautogui`, which drives the X `XTEST` extension via
`python-xlib`. `python-xlib` connects eagerly: importing `pyautogui` (through
its `mouseinfo` dependency) opens the display immediately, before the service
does anything else, so a broken connection here is a crash on start, not a
failure to type later.

Two things GNOME's systemd user environment does not hand a unit for free,
both needed here:

- **`DISPLAY`.** Mutter always runs an `Xwayland` instance for the session
  (confirm with `ps -eo user,cmd | grep Xwayland`; on a single-session
  auto-login machine it is `:0`), and `XTEST` reaches every window through
  it regardless of whether that window is an XWayland client or a native
  Wayland one — Firefox included, even started with `MOZ_ENABLE_WAYLAND=1`.
  But `DISPLAY` itself is never exported into the environment, so the module
  sets it explicitly.
- **`XAUTHORITY`.** Without the matching auth cookie, the connection reaches
  the X server but is refused: `Authorization required, but no authorization
  protocol specified`. Mutter regenerates this file fresh under
  `$XDG_RUNTIME_DIR` on every session start, as
  `.mutter-Xwaylandauth.<random>`, so the wrapper script globs for it at
  launch rather than hardcoding a path.

## Reconnecting

The reader retries the USB connection in a loop rather than exiting: card
readers on a bar countertop get bumped and unplugged. Systemd's own
`Restart = "on-failure"` is a second layer, for a crash the retry loop
itself doesn't catch — though note that a crash *inside* the loop's `try`
never triggers it, since the process itself keeps running; only an
unhandled exception outside the loop, or a leaked resource that wedges every
future attempt in the same process, needs the systemd-level restart.
