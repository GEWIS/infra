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

## Spotify stays out of the keyring

Spotify is a Chromium (CEF) app, and Chromium encrypts its stored data with a
key it keeps in the Secret Service, the GNOME login keyring. That keyring
belongs to [remote access](../service-pc/remote.md): it is deleted and
recreated with the RDP password on every session start. Left alone, Spotify
asks for its key as soon as it starts, and whenever the unlocked keyring is not
yet (or not at that moment) the owner of `org.freedesktop.secrets` it
D-Bus-activates a passwordless daemon that has no keyring at all, which shows
the "choose a password for the new keyring" prompt on screen. Even without the
prompt the key would be thrown away every boot, and with it whatever Spotify
had encrypted.

So Spotify is started with `--password-store=basic`, which makes Chromium use
its built-in key and never talk to the keyring. On this machine that loses
nothing: the keyring password is itself a file the session user can read.
`pcgewisd` has no Spotify, which is why it never showed the prompt.

## NFC login

Members identify themselves at SudoSOS by scanning an NFC card, since there
is no keyboard or mouse. See [NFC reader](../service-pc/nfc.md).

## Remote access

Remote control is enabled and reachable over the NetBird mesh only.
See [Remote access](../service-pc/remote.md).

## Monitoring

The Zabbix agent answers checks over the NetBird mesh only.
See [Zabbix agent](../zabbix-agent.md).