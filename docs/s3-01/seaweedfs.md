# SeaweedFS

One `weed` binary (`pkgs.seaweedfs`, 4.40 at the current nixpkgs pin) running as
a single systemd unit, configured in `nix/hosts/s3-01/seaweedfs.nix`:

```sh
weed server -dir=/var/lib/seaweedfs -ip=127.0.0.1 -ip.bind=127.0.0.1 \
  -master.port=9333 -volume.port=8080 -volume.max=0 \
  -filer -filer.port=8888 \
  -s3 -s3.ip.bind=0.0.0.0 -s3.port=8333 -s3.port.iceberg=0 -s3.iam.readOnly=false
```

| Component | Port | Reachable from |
| --- | --- | --- |
| S3 API **and** IAM API | `:8333` | The mesh and `10.82.50.0/24`. The only port in `networking.firewall.allowedTCPPorts`. |
| Filer | `:8888` | Bound to loopback. Used by `seaweedfs-admin.service` and `weed shell`. |
| Master | `:9333` | Bound to loopback. |
| Volume | `:8080` | Bound to loopback. |

`-ip=127.0.0.1` is the address the components *advertise to each other*, and
`-ip.bind=127.0.0.1` keeps master, volume and filer on the loopback interface so
they are unreachable off-host regardless of the firewall. Only the S3 gateway
overrides that, with `-s3.ip.bind=0.0.0.0`; 8333 is also the only port in
`networking.firewall.allowedTCPPorts`.

`-volume.max=0` lets the volume server grow volumes on demand instead of
pre-allocating a fixed count, and `-s3.port.iceberg=0` switches off the Iceberg
REST catalog listener 4.40 would otherwise open.

## One unit, not four

Master, volume, filer and S3 all run in that one process. `weed server`
sequences them internally — filer at t+1s, S3 at t+2s — and they talk over
in-process and unix sockets. Splitting them into four units was deliberately
rejected: it would mean re-implementing that startup ordering and its readiness
waits in systemd for no gain on a single node. `AF_UNIX` therefore stays in
`RestrictAddressFamilies` despite the otherwise strict hardening
(`ProtectSystem = "strict"`, `SystemCallFilter = @system-service`, and the
rest).

The unit runs as a fixed `seaweedfs` user and group, not `DynamicUser`, because
the sops-nix secret needs a stable owner to be rendered for. State lives under
`StateDirectory = "seaweedfs"`.

## One port, two APIs

8333 serves the S3 API *and* an AWS-IAM-compatible API. There is no separate
admin endpoint: `terraform/seaweedfs-buckets` creates buckets, users, access
keys and policies over that single port with the ordinary `hashicorp/aws`
provider, path-style.

## `-s3.iam.readOnly=false`

Upstream defaults `-s3.iam.readOnly` to **true**. Without the override every IAM
write fails with:

```
AccessDenied: IAM write operations are disabled on this server
```

which means `tofu apply` cannot create a single user or key. Verified against
4.40.

## `-s3.config` is deliberately unset

Identities live in the filer-backed credential store, which is authoritative.
Passing `-s3.config <file>` makes that static file override the filer store
**with no merging**, silently discarding every Terraform-managed key. So there
is no identities file on this host; the only identity Nix creates is the admin
one below, and it is created through the API, not a file.

## Admin bootstrap

`seaweedfs-admin.service` is a oneshot that waits for the filer on 8888 (`curl
--retry`), then runs one `weed shell` command:

```
s3.configure -user admin -access_key … -secret_key … -actions Admin -apply
```

That single admin identity is what OpenTofu authenticates as — the equivalent
of the admin token the previous Garage deployment used.

Its credentials come from the sops template `seaweedfs-admin.env` (mode `0400`,
owner `seaweedfs`), rendered from `secrets/s3-01.yaml` keys
`seaweedfs-admin-access-key` and `seaweedfs-admin-secret-key` into
`AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY`. Rotating either key restarts the
unit, which re-runs `s3.configure`.

Buckets and per-bucket keys are **not** managed here. They are declared in
`terraform/seaweedfs-buckets`, which also mints the credentials into OpenBao —
see [`seaweedfs-buckets`](../seaweedfs-buckets/index.md). Creating a bucket with
`weed shell` puts it outside that state, where the next apply will not see it.

## No bucket quotas

Buckets are unlimited. Size is bounded by the consumers' own retention (30 days
in Loki, Mimir and Tempo), and the backstop is the disk itself.

A quota would not be a limit for these consumers anyway. SeaweedFS enforces one
by flipping the bucket read-only once it is over, and Mimir's compactor and
Loki's retention both have to *write* (compacted blocks, deletion markers)
before they can delete anything, so a full bucket cannot drain itself — it
stays frozen until someone intervenes.

4.40 also has no way for OpenTofu to set one: `PUT /<bucket>?seaweedfs-quota`
arrived in 4.47 ([seaweedfs#11279](https://github.com/seaweedfs/seaweedfs/pull/11279)).
That is the place to start if a bucket ever needs a hard cap; the S3 gateway
already enforces a stored quota on its own every minute.

## Data and metadata

Everything sits under `-dir=/var/lib/seaweedfs`, which is the whole second disk
`/dev/xvdb` (xfs, ~100 GiB, `noatime`) — see [Disks](disks.md). Volume data and
the master meta folder share it, and the filer uses its embedded **leveldb2**
store under that meta folder, so there is no external metadata database to run
or back up separately.

There is one copy of every object on one VM on one storage repository. Treat it
as such and keep a backup elsewhere.

For ad-hoc inspection on the host:

```sh
nix run nixpkgs#seaweedfs -- shell -master=127.0.0.1:9333 -filer=127.0.0.1:8888
```

## Replacing Garage

This host previously ran a single-node Garage cluster on the same disk, mounted
at `/var/lib/garage`. **No data was migrated.** Garage's on-disk format is
unrelated to SeaweedFS's and no importer exists, so the partition was
reformatted at `/var/lib/seaweedfs` and the host rebuilt rather than migrated in
place. The buckets started empty and Loki/Mimir/Tempo retention starts at
cutover — a deliberate choice, because that data is historical and rebuilds by
accrual.

What else changed for anyone holding old notes: ports 3900 (S3) and 3903 (admin)
are gone, replaced by 8333 for both; the client region is `us-east-1`, not
`garage`; and the `garage-rpc-secret` and `garage-admin-token` keys have been
removed from `secrets/s3-01.yaml`.
