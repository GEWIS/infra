# Network

| Interface | Role |
| --- | --- |
| `enp0s31f6` | Uplink, DHCP client |
| `enp1s0` | Booth LAN, static `10.0.0.1/24` |

dnsmasq serves DHCP on `enp1s0` only (`bind-interfaces`, with the uplink
explicitly excluded), handing out `10.0.0.100–200`. The two printers hold
infinite static leases by MAC: `10.0.0.10` and `10.0.0.11`.

On the LAN interface the firewall opens 53/udp, 67/udp, 53/tcp and 22/tcp.
