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
login, and nobody types one here. Left alone the keyring is not even created,
and the only symptom is every client being refused, with

```
[RDP] Credentials are not set, denying client
```

on the machine and `gkr-pam: couldn't unlock the login keyring` earlier in the
journal.

So the module unlocks the keyring itself at session start, creating it on a
fresh machine, using the same secret `passwordFile` points at. Then it stores
the credential and reads it back to confirm, because `grdctl` will happily exit
0 having written nothing if the keyring is not ready yet.

If you are debugging on the machine, the same read-back is:

```console
$ grdctl status --show-credentials
```

`Username: (null)` there means the keyring did not open, and clients are being
denied.
