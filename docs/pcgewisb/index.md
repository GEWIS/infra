# pcgewisb

The bar's Aurora node. A service PC with two screens, each showing one Aurora
page fullscreen, that also forwards the core's DMX frames to the bar lights
and plays its audio.

| Monitor | What is on it |
| --- | --- |
| 1 (left) | Firefox on the URL in the `leftScreenURL` secret |
| 2 (right) | Firefox on the URL in the `rightScreenURL` secret |

`/home/gewis` is carried on `/persist`, so the browser profiles and the
session's PipeWire state survive the root filesystem being wiped on every
boot.

## Aurora services

Two Python services from the `GEWIS/aurora-*` repositories run next to the
session:

| Unit | Runs as | Source | What it does |
| --- | --- | --- | --- |
| `aurora-lights-proxy.service` | system, `DynamicUser` | [aurora-lights-proxy](https://github.com/GEWIS/aurora-lights-proxy) | Receives DMX frames from the core over Socket.IO and forwards them as ArtNet to the lighting controller |
| `aurora-audio-player.service` | user, in the `gewis` session | [aurora-audio-player](https://github.com/GEWIS/aurora-audio-player) | Listens on the core's `/audio` namespace and plays the URLs it is told to through the session's PipeWire |

Both sources are pinned as non-flake inputs in `flake.nix`, so `flake.lock`
holds the commit each unit runs. Bump one with:

```sh
nix flake update aurora-lights-proxy
nix flake update aurora-audio-player
```

Each unit runs `main.py` from its input with a `python3.withPackages`
environment that carries the `requirements.txt` dependencies from nixpkgs,
and restarts five seconds after any exit. The audio player is a user unit so
it shares the session's PipeWire with the browsers; it starts with the
session, not with the display, and needs no window.

## Network

| Interface | Role |
| --- | --- |
| `enp0s31f6` | Uplink, DHCP client via NetworkManager |
| `enp2s0` | Lighting controller, static `169.254.0.1/16`, unmanaged by NetworkManager |

The lights proxy sends ArtNet to `169.254.0.2`, the address the controller
is set to; it sits on its own link because it must not be on the general
network. `enp2s0` is excluded from NetworkManager (which GNOME enables), or
its DHCP profile would take the port and leave it without `169.254.0.1`.
Without that address the ArtNet traffic follows the default route out of the
uplink and never reaches the controller.

If the lights stay dark, check the link before the proxy:

```sh
ip -br addr show enp2s0       # 169.254.0.1/16, UP
ip route get 169.254.0.2      # must say "dev enp2s0"
ping -c3 169.254.0.2
sudo nix run nixpkgs#tcpdump -- -ni enp2s0 udp port 6454   # ~40 packets/s
```

## Audio

`services.pipewire` with the PulseAudio shim is enabled for the session, which
is what both libvlc and Firefox talk to. Pick the output device as the
session user:

```sh
sudo -u gewis XDG_RUNTIME_DIR=/run/user/1000 wpctl status            # lists the sinks
sudo -u gewis XDG_RUNTIME_DIR=/run/user/1000 wpctl set-default <id>  # selects one
```

## Secrets

`secrets/pcgewisb.yaml` carries, besides `cbcPassword`, `rdpPassword` and
`netbird-setupkey`, the two screen URLs and one environment file per Aurora
unit. Each environment file is a multi-line string that systemd reads as
`EnvironmentFile`; `LOG_LEVEL` is `INFO` on the units and a line here
overrides it:

```yaml
leftScreenURL: https://<aurora core>/...
rightScreenURL: https://<aurora core>/...
aurora-lights-proxy: |
  URL=https://<aurora core>
  API_KEY=<key for the lights proxy>
aurora-audio-player: |
  URL=https://<aurora core>
  API_KEY=<key for the audio player>
```

A changed `aurora-lights-proxy` restarts its unit on the next switch. The
audio player is a user unit, which sops-nix cannot restart; log out or
`systemctl --user -M gewis@ restart aurora-audio-player` after changing its
key.

## Installing

[Installing](../service-pc/install.md), with the secrets above. After the
first boot check the Aurora units as well as the session:

```sh
systemctl status aurora-lights-proxy
systemctl --user -M gewis@ status aurora-audio-player
```

## Remote access

Remote control is enabled and reachable over the NetBird mesh only.
See [Remote access](../service-pc/remote.md).

## Monitoring

The Zabbix agent answers checks over the NetBird mesh only.
See [Zabbix agent](../zabbix-agent.md).
