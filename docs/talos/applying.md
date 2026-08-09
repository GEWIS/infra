# Applying

`config-apply` and `bootstrap` connect **directly to node IPs** on
`10.82.50.0/24:50000`, so they must run from a host with a real route to that
subnet — the on-site LAN or the VPN. VM create and destroy go through the public
`xoa.gewis.nl` API and work from anywhere. Before an apply that includes the node
steps, confirm the route with a single probe that actually returns:

```sh
talosctl -n 10.82.50.101 get disks --insecure
```

Then apply:

```sh
cd terraform/talos-hosts
tofu init
tofu apply
```

A single `tofu apply` creates the three VMs and, in the same run, pushes each
machine configuration and bootstraps etcd. The config-apply and bootstrap steps
each carry a `timeouts.create` long enough to ride through a node's cold boot
into maintenance mode, so they no longer need a separate `-target=module.vm`
stage ahead of them. Confirm disk sizing after the apply (`talosctl -n <ip> get
disks --insecure`, or XO); the empty-CD template fixes the disk-scramble bug
that the old pre-check guarded against.

Each node boots the nocloud image with **no config source** (`cloud_config =
null`, so it has no config drive) and sits in maintenance mode on its reserved
address. `tofu apply` then pushes the machine configuration over the API; the
node writes it, installs to `/dev/xvda`, and reboots into the configured system;
`talos_machine_bootstrap` runs etcd genesis on `talos-01` only.

A first apply can race a node reaching maintenance mode or rebooting — a
config-apply that errors with a connection failure just means the node was not up
yet. Re-run; every step is idempotent.

The module wires the `talos-1.13.8-nocloud` template, 20 GiB root / 10 GiB data
disks, `cloud_config = null`, and `machine.time.servers = ["time.gewis.nl"]` (the
nodes cannot reach the default Cloudflare NTP pool). The Longhorn
`UserVolumeConfig` rides along as a config patch. The old metal-ISO wiring is
gone — `iso_name`, the `data "xenorchestra_vdi" "iso"` block, and the module's
`cdrom_id` argument were all removed; the module keeps an optional `cdrom` block
that is a no-op while `cdrom_id` is null, since the empty CD now lives on the
template itself.
