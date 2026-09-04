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

## Touch

| Option | Default | Meaning |
| --- | --- | --- |
| `touch.enable` | `false` | This host is a touchscreen with no keyboard or mouse |
| `touch.onScreenKeyboard` | `true` | GNOME's on-screen keyboard |

See [Touchscreens and workspaces](touch.md).

## Browser

The browser is always Firefox. The policy file below is Firefox's and the
launcher sets `MOZ_ENABLE_WAYLAND`, so another browser would come up with
neither — there is nothing to gain from making it configurable.

| Option | Default | Meaning |
| --- | --- | --- |
| `browser.enable` | `false` | Run Firefox |
| `browser.url` | `null` | URL to open. Exactly one of this or `urlFile` |
| `browser.urlFile` | `null` | File read at launch, for when the URL is itself a secret |
| `browser.kiosk` | `false` | Fullscreen, with no GNOME top bar and no tab strip. Also hides the window list and swallows edge gestures |
| `browser.waitForUrl` | `true` | Poll the URL before starting, so a fast-booting PC does not land on an error page |
| `browser.waitTimeout` | `120` | Seconds to poll before starting anyway; `0` waits forever |

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
