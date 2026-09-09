# Zabbix agent

`gewis.zabbixAgent` runs the Zabbix agent on a host so the Zabbix server can
poll it for CPU, memory, disk, network and service state. It is defined in
`nix/modules/zabbix-agent.nix`, imported by every host through
`nix/modules/default.nix`, and does nothing until a host sets
`gewis.zabbixAgent.enable`.

```nix
gewis.zabbixAgent = {
  enable = true;
  firewallInterfaces = [ "nb-netbird" ];
};
```

| Host | Enabled |
| --- | --- |
| [`pcgewisc`](pcgewisc/index.md) | yes, over the mesh |
| [`pcgewisd`](pcgewisd/index.md) | yes, over the mesh |
| [`pcgewisinfo`](pcgewisinfo/index.md) | yes, over the mesh |

## Passive checks only

The server opens the connection and the agent answers, so the server has to be
able to reach port `10050` on the host. The service PCs sit behind a NAT on the
booth LAN, so the route that works is the NetBird mesh: put the mesh interface
in `firewallInterfaces` and the port is open there and nowhere else.
`openFirewall` opens it on every interface instead, which hands the host's
metrics to anything on the LAN.

## The server address

`server` is the list of addresses the agent accepts checks from, and it is
matched against the **source address the server connects from**. Over the mesh
that is the server's mesh address, not the address `zabbix.gewis.nl` resolves to
on the public internet. If checks come back as
`Received empty response from Zabbix Agent` while the port is open, this is
almost always why: run

```console
$ journalctl -u zabbix-agent
```

on the host and look for `failed to accept an incoming connection: connection
from "..." rejected, allowed hosts: "..."`. The address in that line is what
`server` has to contain.

## Adding a host

Set `gewis.zabbixAgent.enable` in `nix/hosts/<host>/`, give it the interface the
server reaches it on, and register the host in Zabbix under the name
`networking.hostName` — the agent reports the system hostname unless the host
overrides `services.zabbixAgent.settings.Hostname`.
