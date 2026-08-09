# Accounts

| User | Purpose |
| --- | --- |
| `gewis` | uid 1000, no password, runs the kiosk session |
| `cbc` | Administrator, in `wheel`, password from the `cbcPassword` secret |

`wheelNeedsPassword` is off, and `users.allowNoPasswordLogin` is on because
`gewis` deliberately has an empty password.

sshd allows password authentication for `cbc` and refuses root outright. It is
**not** opened globally: `openFirewall = false`, and port 22 is allowed only on
the LAN interface.
