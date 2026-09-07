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

## Typing works on Wayland, not just XWayland

The service is a plain `graphical-session.target` unit, same as the browser
and the other apps, and it types using `pyautogui`, which drives the X
`XTEST` extension. That might look like it only reaches XWayland clients, but
Mutter's Wayland compositor implements `XTEST` as a synthetic input device fed
into the same input pipeline real hardware uses, so it lands on whichever
window has focus — Firefox included, even started with
`MOZ_ENABLE_WAYLAND=1`. Nothing here forces an X11 session or an XWayland
fallback on purpose; it is not needed.

## Reconnecting

The reader retries the USB connection in a loop rather than exiting: card
readers on a bar countertop get bumped and unplugged. Systemd's own
`Restart = "on-failure"` is a second layer, for a crash the retry loop
itself doesn't catch.
