# pcgewisinfo

The info-screen kiosk. It also serves DHCP and printing for the small LAN behind
it. Installed as described in [Installing](../service-pc/install.md); updated
automatically by comin.

It stays on at night; the browser and `geprint` are restarted at 04:30. See
[Nightly restart](../service-pc/options.md#nightly-restart).

## Monitoring

The Zabbix agent answers checks over the NetBird mesh only.
See [Zabbix agent](../zabbix-agent.md).
