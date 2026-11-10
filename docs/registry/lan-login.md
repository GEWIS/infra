# LAN login

zot grants nothing anonymously, yet nodes pull from `registry.net.gewis.nl`
without credentials. The `zot-lan-reader` Middleware sets
`Authorization: Basic <lan-reader:…>` on every request on the `zot-lan` route,
replacing whatever the client sent. zot checks Basic credentials against its
htpasswd file before it would challenge, so the client never sees a `401` and
needs no login, `docker pull` included.

`lan-reader` is an ordinary logged-in user and can only `read`. The route also
admits only `GET` and `HEAD` under `/v2/`, so pushes and the UI work on
`registry.gewis.nl` only, and it passes through `zot-no-session`, see
[Sessions and keys](sessions.md).

| Piece | Where |
| --- | --- |
| Password | Secret `zot-lan-reader`, from the `Password` generator of the same name in `flux/50_apps/zot/external-secrets.yaml` |
| htpasswd file | Secret `zot-htpasswd`, rendered by `zot-values`, mounted at `/secrets/htpasswd` |
| Middleware | `zot-lan-reader`, rendered by `zot-values`, see [The config](config.md) |

The password is generated once (`refreshPolicy: CreatedOnce`). zot polls the
htpasswd file every second and reloads it when the mounted Secret changes.
Deleting the Secret `zot-lan-reader` generates a new password: the Middleware
switches as soon as `zot-values` upgrades, zot once the kubelet has updated the
mounted Secret, and LAN pulls get `401` in between.

The password sits in the Middleware and the `zot-values` Helm release,
readable by cluster admins, and it also works on `registry.gewis.nl`: it reads
every image from anywhere, and pushes nothing. No session or key can be made
with it, see [Sessions and keys](sessions.md).
