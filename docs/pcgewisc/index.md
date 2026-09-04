# pcgewisc

A service PC for the bar: the SudoSOS point of sale in a browser, and a Spotify
client for the music. A touchscreen, with no keyboard or mouse attached.

| Workspace | What is on it |
| --- | --- |
| 1 | Firefox on <https://sudosos.gewis.nl/pos> |
| 2 | Spotify |

## Spotify has to be signed in by hand, once

There is no way to hand Spotify credentials from configuration, its client
only takes an interactive login. It does keep the session afterwards, and
`/home/gewis` is carried on `/persist` alongside the rest of this host's
state, so the login only has to be done once per install even though the root
filesystem itself is wiped on every boot.

## Remote access

Remote control is enabled and reachable over the NetBird mesh only.
See [Remote access](../service-pc/remote.md).