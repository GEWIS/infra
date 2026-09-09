# pcgewisd

A service PC running the SudoSOS point of sale in a browser. A touchscreen,
with no keyboard or mouse attached.

| Workspace | What is on it |
| --- | --- |
| 1 | Firefox on <https://sudosos.gewis.nl/pos> |

`/home/gewis` is carried on `/persist`, so the browser profile survives the
root filesystem being wiped on every boot.

## NFC login

Members can identify themselves at SudoSOS by scanning an NFC card, . See [NFC reader](../service-pc/nfc.md).

## Remote access

Remote control is enabled and reachable over the NetBird mesh only.
See [Remote access](../service-pc/remote.md).

## Monitoring

The Zabbix agent answers checks over the NetBird mesh only.
See [Zabbix agent](../zabbix-agent.md).
