# Accounts

| User | Purpose |
| --- | --- |
| `gewis` | uid 1000, no password, runs the desktop session. Created by the [service-PC module](../service-pc/index.md) |
| `cbc` | Administrator, in `wheel`, password from the `cbcPassword` secret |

`wheelNeedsPassword` is off.

`gewis` has no password at all, rather than the empty one it used to have. GDM's
autologin never consults `pam_unix` for authentication, so logging the session in
does not need one, and an empty password would have left the account open to
anyone reaching a TTY.

sshd allows password authentication for `cbc` and refuses root outright. It is
**not** opened globally: `openFirewall = false`, and port 22 is allowed only on
the LAN interface.
