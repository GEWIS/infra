# pcgewisa

A service PC with two screens, each showing one Aurora page fullscreen.
Nothing else runs on it; the Aurora lights and audio services live on
[pcgewisb](../pcgewisb/index.md).

| Monitor | What is on it |
| --- | --- |
| 1 (left) | Firefox on the URL in the `leftScreenURL` secret |
| 2 (right) | Firefox on the URL in the `rightScreenURL` secret |

`/home/gewis` is carried on `/persist`, so the browser profiles survive the
root filesystem being wiped on every boot.

## Secrets

`secrets/pcgewisa.yaml` carries `cbcPassword`, `rdpPassword`,
`netbird-setupkey` and the two screen URLs:

```yaml
leftScreenURL: https://<aurora core>/...
rightScreenURL: https://<aurora core>/...
```

## Installing

[Installing](../service-pc/install.md), with the secrets above.

## Remote access

Remote control is enabled and reachable over the NetBird mesh only.
See [Remote access](../service-pc/remote.md).

## Monitoring

The Zabbix agent answers checks over the NetBird mesh only.
See [Zabbix agent](../zabbix-agent.md).
