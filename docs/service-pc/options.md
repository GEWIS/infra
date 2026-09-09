# Options

Everything below is under `gewis.servicePc`, defined in
`nix/modules/service-pc/`.

## Session

| Option | Default | Meaning |
| --- | --- | --- |
| `enable` | `false` | Turn the whole thing on |
| `user` | `"gewis"` | Unprivileged user the session and its applications run as. The module creates it |
| `uid` | `null` | Fixed uid, also used as the primary group's gid. Pin it where state outlives reinstalls |
| `workspaces` | `1` | Number of static workspaces |
| `multiMonitor` | `false` | This host has more than one screen; enables per-monitor placement |
| `justPerfection` | `false` | Load the Just Perfection extension |

## Touch

| Option | Default | Meaning |
| --- | --- | --- |
| `touch.enable` | `false` | This host is a touchscreen with no keyboard or mouse |
| `touch.onScreenKeyboard` | `true` | GNOME's on-screen keyboard |

See [Touchscreens and workspaces](touch.md).

## Browser

The browser is always Firefox. The policy file below is Firefox's and the
launcher sets `MOZ_ENABLE_WAYLAND`.

| Option | Default | Meaning |
| --- | --- | --- |
| `browser.enable` | `false` | Run Firefox |
| `browser.url` | `null` | URL to open. Exactly one of this or `urlFile` |
| `browser.urlFile` | `null` | File read at launch, for when the URL is itself a secret |
| `browser.kiosk` | `false` | Fullscreen once the window appears, by sending F11 until it takes |
| `browser.waitForUrl` | `true` | Poll the URL before starting, so a fast-booting PC does not land on an error page |
| `browser.waitTimeout` | `120` | Seconds to poll before starting anyway; `0` waits forever |

`kiosk` waits for Firefox's window, raises it, and sends F11 through `ydotool`,
repeating the press until GNOME reports the window as fullscreen. Firefox keeps
only a fullscreen state it entered itself, and F11 is a toggle, so each press is
checked.

### When it does not go fullscreen

`kiosk` runs as an `ExecStartPost` of the `service-pc-browser` user unit, so
everything it says is in that unit's journal. It is a *user* unit, so ask for it
by that name rather than with `--user`, which would look at root's own manager:

```console
$ sudo journalctl -b _SYSTEMD_USER_UNIT=service-pc-browser.service -o cat
```

The helper always logs why it gave up, and the four messages mean different
things:

- *`org.gnome.Shell.Extensions.Windows never answered`* — the
  [window-calls](https://github.com/ickyicky/window-calls) extension is not
  running, so nothing here can work. It is pulled in automatically by `kiosk`
  and by `workspace`/`monitor`, but GNOME disables an extension that does not
  declare support for the running shell version. Check with `gnome-extensions
  list --enabled` in the session, and look for `JS ERROR` in the shell's own
  log: `sudo journalctl -b _COMM=gnome-shell`.
- *`no window with wm_class 'firefox' … saw: …`* — the extension answered, but
  nothing it listed matched. The `saw:` list is the set of classes Mutter
  actually reports; if Firefox is in there under another name, that name is
  what the helper should be matching on.
- *`ydotool failed on attempt N: …`* — the keystroke never left the tool, and
  the message is ydotool's own. Almost always `ydotoold` not running or its
  socket not readable; see [the NFC page](nfc.md), which uses the same daemon.
- *`… is still not fullscreen after N F11 presses`* — the keystrokes went out
  and the window still is not fullscreen. The line after it dumps what GNOME
  reports for that window, so compare its `width`/`height` against the monitor.

## Applications

`apps` is an attribute set; the name is the attribute key.

| Option | Default | Meaning |
| --- | --- | --- |
| `apps.<name>.package` | *required* | Package providing the application |
| `apps.<name>.exec` | `null` | Command to run; defaults to the package's `meta.mainProgram` |
| `apps.<name>.wmClass` | `<name>` | Window class the placement helper matches on |

## Placement

Both the browser and each app take these:

| Option | Default | Meaning |
| --- | --- | --- |
| `workspace` | `null` | One-based workspace to move the window to |
| `monitor` | `null` | One-based logical monitor to move it to, and maximise it there |

A window is placed on one or the other, never both, and `monitor` requires
`multiMonitor`. Leaving both `null` lets GNOME put the window wherever it likes.
A window that is placed is also maximised, so it fills the screen it landed on.

## NFC reader

| Option | Default | Meaning |
| --- | --- | --- |
| `nfcReader.enable` | `false` | Run the background NFC reader |
| `nfcReader.vendorId` | `"072f"` | USB vendor ID, from `lsusb` |
| `nfcReader.productId` | `"2200"` | USB product ID, from `lsusb` |

See [NFC reader](nfc.md).

## Remote access

| Option | Default | Meaning |
| --- | --- | --- |
| `remote.enable` | `false` | Remote control of the live session over RDP |
| `remote.port` | `3389` | Port the RDP server listens on |
| `remote.username` | `null` | Username clients authenticate with; defaults to `user` |
| `remote.passwordFile` | *required when enabled* | File holding the password, readable by `user` |
| `remote.openFirewall` | `false` | Open the port on every interface |
| `remote.firewallInterfaces` | `[ ]` | Interfaces to open the port on |

See [Remote access](remote.md).
