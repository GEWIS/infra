# Accounts

| User | Purpose |
| --- | --- |
| `gewis` | uid 1000, no password, runs the desktop session. Created by the [service-PC module](../service-pc/index.md) |
| `cbc` | Administrator, in `wheel`, password from the `cbcPassword` secret. Created by `gewis.admin` |

`wheelNeedsPassword` is off.

`gewis` has no password at all. GDM's autologin never consults `pam_unix` for
authentication, so logging the session in does not need one, and an empty
password would leave the account open to anyone reaching a TTY.

sshd allows password authentication for `cbc` and refuses root outright. It is
**not** opened globally: port 22 is allowed on the booth LAN interface and on
the NetBird mesh, nowhere else. The ed25519 host key is persisted, so the key
a client has pinned stays valid across reboots.
