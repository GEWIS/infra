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
node. The module tags it `uaccess`:

```
SUBSYSTEM=="usb", ATTRS{idVendor}=="072f", ATTRS{idProduct}=="2200", TAG+="uaccess"
```

`uaccess` grants the device to whoever is logged in at the seat, which on a
service PC is always the one auto-login session user. It does not go stale if
`user` is ever renamed.

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

If the service ever logs a `Device or resource busy` retry loop, check
`lsmod | grep pn533`. The claimant is a kernel module, so neither `lsof` on the
device node nor `ps` shows it.

## Typing

Typing goes through [`programs.ydotool`](https://github.com/ReimuNotMoe/ydotool),
which injects input through `/dev/uinput` — a kernel-level virtual input device
indistinguishable from a real keyboard. Nothing in the session has to approve
it, and it needs no `DISPLAY`/`XAUTHORITY` wiring.

`programs.ydotool.enable` creates the `ydotoold` system service and a
`ydotool` group gating access to its socket; the session user is added to
that group. The script calls the `ydotool` CLI directly:

```console
$ ydotool type 'nfc04a1b2c3d4'
$ ydotool key 28:1 28:0   # Enter (evdev KEY_ENTER, press then release)
```

## Reconnecting

The reader retries the USB connection in a loop: card readers on a bar
countertop get bumped and unplugged. Systemd's `Restart = "on-failure"` is a
second layer, for a crash the retry loop itself doesn't catch. A crash *inside*
the loop's `try` never triggers it, since the process keeps running; only an
unhandled exception outside the loop, or a leaked resource that wedges every
future attempt in the same process, reaches the systemd-level restart.
