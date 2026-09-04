# Remote access

`remote.enable` lets you take over the session that is physically on the
machine's screen.

```nix
gewis.servicePc.remote = {
  enable = true;
  passwordFile = config.sops.secrets.rdpPassword.path;
  firewallInterfaces = [ config.services.netbird.clients.netbird.interface ];
};
```

## Connecting
Host is the machine's mesh name and port 3389; the username defaults to the
session user (`gewis`) and the password is whatever `passwordFile` contains.

The server requires **NLA**, so a client that has been forced to plain TLS will
be turned away with `HYBRID_REQUIRED_BY_SERVER`. Every normal client negotiates
NLA by default.

## Reachability

The firewall stays shut by default. Prefer `firewallInterfaces`, which opens
the port only on the named interfaces, normally the NetBird mesh.

## Where the password lives

`gnome-remote-desktop` keeps its password in libsecret, which in practice means
the GNOME login keyring. On a service PC that keyring is never unlocked: GDM's
autologin PAM stack only unlocks it when a password was actually typed at
login, and nobody types one here. Worse, `pam_gnome_keyring`'s `auto_start`
still launches a keyring daemon for the session, without a password, and that
daemon owns `org.freedesktop.secrets`. A second `gnome-keyring-daemon --unlock`
cannot take the name over, so unlocking after the fact does nothing: GNOME
starts asking on screen for a keyring password, and every client is refused
with

```
[RDP] Credentials are not set, denying client
```

on the machine and `gkr-pam: no password is available for user` earlier in the
journal.

So the module runs the keyring daemon itself, as a session service that
`--replace`s the passwordless one and unlocks the login keyring with the same
secret `passwordFile` points at, creating it if it is not there. It deletes
`~/.local/share/keyrings` first: a keyring left behind by an earlier boot, or by
the on-screen "set a password" prompt, has a password nobody knows and would
lock the session out for good. Nothing of value is in there, because the RDP
credential is stored again on every session start.

Storing is a store-and-read-back loop, because `grdctl` exits 0 having written
nothing while the keyring is not ready yet. On the machine, the same read-back
is:

```console
$ grdctl status --show-credentials
```

Run it as the session user (`gewis`), in that session: `grdctl` talks to the
session bus, so as any other user it reports that user's own empty
configuration and an inactive unit. `Username: (empty)` for `gewis` means the
keyring did not open, and clients are being denied.
