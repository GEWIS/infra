# Garage

A single node, configured in `nix/hosts/s3-01/garage.nix`.

| Endpoint | Bound to | Reachable from |
| --- | --- | --- |
| S3 API, `:3900` | `[::]` | The mesh and `10.82.50.0/24`. The host has no WAN leg, so opening the port in the firewall is exactly that reach and nothing wider. |
| RPC, `:3901` | `[::1]` | Nothing. A one-node cluster has no peer to talk to, and the CLI is local. |
| Admin API, `:3903` | `[::]` | The mesh and `10.82.50.0/24`, same reach as the S3 API. `terraform/garage-buckets` drives it from an operator workstation on the campus LAN. |

`replication_factor = 1`, so **this stores one copy of every object and
tolerates no failure at all.** It is a single VM on a single storage
repository; treat it as such and keep a backup elsewhere. Raising the factor
later is not a config edit — it means deleting `cluster_layout` on every node
and rebalancing from scratch.

Buckets are addressed **path-style**, `http://<host>:3900/<bucket>/<key>`.
`root_domain` is deliberately unset, because vhost-style addressing needs a
wildcard DNS record and the host's LAN address moves with DHCP. Point clients
at region `garage` and set `force_path_style` (boto3: `addressing_style =
"path"`).

`rpc_secret` and `admin_token` come from `secrets/s3-01.yaml` through
`rpc_secret_file`/`admin_token_file`, never inline in `/etc/garage.toml`, which
is world-readable in the store. Garage refuses to start on a world-readable
secret file, so the sops secrets are `0400 garage:garage`.

## Why the static user

`DynamicUser = false` plus a static `garage` user is load-bearing, not
tidiness. The nixpkgs module defaults `metadata_dir`/`data_dir` under
`/var/lib/garage` and reacts to that prefix with `StateDirectory = "garage"`
alongside `DynamicUser = lib.mkDefault true`. systemd only uses the
`/var/lib/private` indirection for dynamic users, so that combination puts the
real data on the 40 GiB root disk and leaves a symlink where the mount should
be.

The `users.users.garage`/`users.groups.garage` declarations are not optional
either. The module creates no static account, so overriding `User` without
declaring it makes the unit fail at `step USER` on start. The build succeeds
either way; it only surfaces at runtime. Verify with `readlink
/var/lib/garage` (must print nothing) and `findmnt /var/lib/garage`.

## The layout is not in Nix

Garage stores its cluster layout in its own metadata, so it is bootstrapped
once by hand and then survives reboots and rebuilds. Done already; repeat it
only after a reinstall, which wipes `xvdb`:

```sh
garage status                                  # read the node ID
garage layout assign <node-id> -z gewis -c 90G
garage layout apply --version 1
```

`-c` is the capacity the node advertises, not a quota — keep it under the
partition size. 90G on the 100 GiB disk leaves headroom; Garage reports the
usable figure as 83.8 GiB.

Buckets and access keys are **not** managed here. They are declared in
`terraform/garage-buckets`, which also mints the credentials into OpenBao — see
[`garage-buckets.md`](../garage-buckets/index.md). Creating them with `garage bucket
create` puts them outside that state, where the next apply will not see them.

The layout commands above need root on the host: the CLI reads
`/etc/garage.toml` for the RPC secret path, and that secret is only readable by
root and `garage`.
