# talos

A three-node Talos Linux Kubernetes cluster on XCP-ng, one node per physical
host. OpenTofu creates the VMs and hands each one its machine configuration over
the Talos API; there is no SSH and no nixos-anywhere here.

## How it fits together

Talos lives in its own OpenTofu root, `terraform/talos/`, with its own state
(`talos/terraform.tfstate`) and its own secret. It shares only the `xcpng-vm`
module with `s3-01`. The two roots reference nothing of each other's: the
cluster reaches Garage as an ordinary S3 client over the network, never through
tofu. Splitting them means a Talos apply cannot touch `s3-01`, and a Talos plan
skips `s3-01`'s three-minute closure build.

`s3-01` and `talos` both encrypt their state the same way, in the same bucket,
under the same passphrase from `secrets/tofu.yaml`. Each root is a separate
`tofu init`.

## The template is a manual prerequisite

The provider can clone a template but cannot build one — `template` is
`Required` and forces replacement, and there is no way to attach an uploaded
disk as a VM's boot disk. So the Talos image becomes a template **by hand,
once**. Talos upgrades afterwards go through `talosctl upgrade`, never a
re-import.

The template is the **nocloud** disk image: Talos baked onto the disk, so a
clone boots straight from its own disk with no ISO and no runtime dependency on
any ISO SR. Given no config source it lands in maintenance mode on its reserved
address, waiting for tofu to push the machine configuration over the API.

The image is built at [Image Factory](https://factory.talos.dev) with a
schematic carrying four extensions:

| Extension | Why |
| --- | --- |
| `siderolabs/xen-guest-agent` | reports guest IPs to Xen Orchestra |
| `siderolabs/iscsi-tools` | Longhorn needs `iscsiadm`, or volumes never attach |
| `siderolabs/util-linux-tools` | Longhorn needs `fstrim` |
| `siderolabs/netbird` | baked in but dormant; activated by an `ExtensionServiceConfig`, never a re-image |

The schematic id is
`544579955b64479597e31a593d522bfa8c9ce21939264e852e54c55e11b4d788` — a content
hash of exactly those four, verified against the Factory. It is pinned in
`main.tf` as both the template name and `machine.install.image`.

### The disk-scramble bug, and why the template carries an empty CD drive

The template ships with **one bootable disk plus an empty CD drive**, mirroring
the shape of the working `s3-01` Ubuntu template. The empty CD is not cosmetic —
it is the fix for a provider bug.

`terra-farm/xenorchestra` v0.40.0 **scrambles the two `disk` blocks when cloning
a template that has no CD drive**: both disks come out at the second block's size
(10/10 GiB), silently losing the 20 GiB system disk, sometimes with
non-deterministic device names too. A CD drive present on the template makes disk
sizing correct. Proven again this session — the nocloud template with an empty CD
cloned to a correct 20 GiB root + 10 GiB data on all three nodes, across hosts.
`s3-01`, which has always sized correctly, happens to carry exactly this shape:
OS on the disk plus an empty CD drive.

An **empty** CD is chosen deliberately because it needs no ISO and no ISO SR at
runtime: its boot order is irrelevant, because an empty drive has nothing to
boot, so UEFI/OVMF falls through to the disk. (`s3-01` boots CD-first, `dcn`, and
still comes up off its disk for exactly this reason.)

This is why the earlier **diskless template + bootable metal-ISO** approach was
abandoned. The provider has no boot-order attribute (confirmed for every released
version) and no CD-eject. With a blank disk and a bootable Talos metal ISO in a
CD-first VM, OVMF boots the ISO on every reboot: the node installs to `/dev/xvda`,
reboots, and lands straight back in the ISO — a maintenance-mode loop where
bootstrap never completes. Escaping it would need a manual, out-of-band
`vm.setBootOrder` / `ejectCd` per node, only reachable through xo-cli's JSON-RPC
(not the REST API, not the provider). nocloud + empty CD avoids all of it, needs
zero boot-order management, and has no runtime coupling to the flaky SMB ISO SR.

### Building the template

Named `talos-1.13.8-nocloud`, UEFI (no Secure Boot). The provider cannot do any
of this, so it is done once by hand with the XO REST API and `xo-cli`.

1. Download the nocloud disk image from Image Factory and decompress it:

   ```sh
   curl -LO "https://factory.talos.dev/image/544579955b64479597e31a593d522bfa8c9ce21939264e852e54c55e11b4d788/v1.13.8/nocloud-amd64.raw.xz"
   unxz nocloud-amd64.raw.xz
   ```

2. Convert the raw image to a **dynamic** VHD, which shrinks the upload from
   ~4.45 GiB raw to ~280 MiB:

   ```sh
   qemu-img convert -O vpc -o subformat=dynamic nocloud-amd64.raw talos-1.13.8-nocloud.vhd
   ```

3. Import the VHD as a VDI into a disk SR over the XO REST API (default upload
   format is VHD; pass `raw=true` only for a raw image):

   ```sh
   curl -b "authenticationToken=$XOA_TOKEN" \
     -H "Content-Type: application/octet-stream" \
     --data-binary @talos-1.13.8-nocloud.vhd \
     "https://xoa.gewis.nl/rest/v0/srs/<sr-uuid>/vdis?name_label=talos-1.13.8-nocloud-disk"
   ```

4. Build the template VM with `xo-cli` (JSON-RPC — the empty-CD trick is not
   expressible over REST). Authenticate once, then create the VM from a
   UEFI-capable base template, attach the imported disk as the boot disk, add an
   empty CD drive, and convert to a template. Note that pool templates are
   addressed by a **composite** id, `<pool-uuid>-<template-uuid>`:

   ```sh
   npx --yes xo-cli register --token "$XOA_TOKEN" https://xoa.gewis.nl
   npx --yes xo-cli vm.create name_label=talos-1.13.8-nocloud \
     template=<pool-uuid>-<GenericLinuxUEFI-uuid> hvmBootFirmware=uefi bootAfterCreate=false
   npx --yes xo-cli vm.attachDisk vm=<vm-uuid> vdi=<imported-vdi-uuid> bootable=true position=0
   # insert any ISO then eject it — leaves an empty CD drive attached (the disk-scramble fix)
   npx --yes xo-cli vm.insertCd id=<vm-uuid> cd_id=<any-iso-vdi-uuid> force=true
   npx --yes xo-cli vm.ejectCd id=<vm-uuid>
   npx --yes xo-cli vm.convertToTemplate id=<vm-uuid>
   ```

The result is a template with one bootable disk (the nocloud image) at position 0
plus one empty CD drive, UEFI — the same shape as the `s3-01` template. A full
clone resizes the system disk to 20 GiB and Talos grows its EPHEMERAL partition
into the space on first boot. Rename the `template_name_label` local in `main.tf`
if you name the template something other than `talos-1.13.8-nocloud`.

This session imported the VHD into `vhost1-ssd2`
(`bfd38322-f414-da7c-e97e-68d5c8d7fa44`); the resulting template is XO
`86690565-d9a7-2655-ca7c-58f10246a93a`, boot order `cdn`.

## Other prerequisites

- **Three DHCP reservations** on the `10.82.50.0/24` server, pinning the pinned
  MACs to fixed addresses. The nodes run DHCP; the reservation is what makes the
  address stable and collision-safe. tofu sets the MACs; the reservation keys off
  them, so the two must match exactly.

  | Node | MAC | Address |
  | --- | --- | --- |
  | talos-01 | `00:16:3e:5e:b8:01` | 10.82.50.101 |
  | talos-02 | `00:16:3e:5e:b8:02` | 10.82.50.102 |
  | talos-03 | `00:16:3e:5e:b8:03` | 10.82.50.103 |

- **`kube.gewis.nl`** with an A record to each of the three addresses. It is the
  API endpoint, baked into every kubeconfig and every certificate SAN, so it is
  effectively permanent — a DNS name rather than an IP precisely so a node can be
  replaced without reissuing PKI. There is deliberately no Talos VIP: it is
  IPv4-only and depends on etcd, unusable exactly when the API is in trouble.

- The `10.82.50.0/24` subnet is already a NetBird routing-peer resource, so the
  nodes are reachable over the mesh the moment they boot, with no NetBird on them.

## Applying

`config-apply` and `bootstrap` connect **directly to node IPs** on
`10.82.50.0/24:50000`, so they must run from a host with a real route to that
subnet — the on-site LAN or the VPN. VM create and destroy go through the public
`xoa.gewis.nl` API and work from anywhere. Before an apply that includes the node
steps, confirm the route with a single probe that actually returns:

```sh
talosctl -n 10.82.50.101 get disks --insecure
```

Then apply in two stages, so a disk-sizing check can sit between them:

```sh
cd terraform/talos
tofu init
tofu apply -target=module.vm     # create the 3 VMs
# confirm each node's xvda = 20 GiB and xvdb = 10 GiB (talosctl ... get disks --insecure, or XO)
tofu apply                       # config-apply + etcd bootstrap
```

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

## Secrets never reach the state

`talos_machine_secrets` would write five CA private keys, the bootstrap token
and the etcd encryption secrets into the state file. Instead the PKI is minted
once with `talosctl gen secrets`, stored sops-encrypted in `secrets/talos.yaml`,
and decrypted by `.envrc` into `TF_VAR_talos_secrets`. `main.tf` remaps its keys
into the shape the provider wants and feeds it only through `ephemeral` blocks
and write-only (`*_wo`) inputs. The state holds resource ids, node addresses and
a non-secret `machine_configuration_hash` — nothing else. That hash is how the
provider detects config drift without persisting the config: write-only values
are still present during a run, just never written down.

The provider's `ephemeral talos_machine_secrets` is not an alternative — it has
no seed input, so every open mints fresh CAs and would orphan a running cluster.

### kubeconfig and talosconfig

Generated locally from the same sops bundle, never through tofu, so no admin
credential lands in state either:

```sh
sops -d secrets/talos.yaml > /tmp/talos-secrets.yaml
talosctl gen config cbc https://kube.gewis.nl:6443 \
  --with-secrets /tmp/talos-secrets.yaml --output-types talosconfig -o talosconfig
talosctl --talosconfig talosconfig --nodes 10.82.50.101 kubeconfig
rm /tmp/talos-secrets.yaml
```

`kube.gewis.nl` is the Kubernetes API endpoint only — A records to all three
nodes on `:6443` — and belongs in the kubeconfig. For `talosctl`, use the
**node IPs** as endpoints: the Talos apid certificate (from `certs.os`) does not
carry `kube.gewis.nl` in its SANs unless it is added to `machine.certSANs`.

## The cluster has no CNI until you install one

`cluster.network.cni.name = none` and `cluster.proxy.disabled = true`: Talos
ships neither Flannel nor kube-proxy here. After bootstrap the nodes stay
`NotReady` until Cilium is installed, which is a Helm/Flux concern, not tofu.
Cilium replaces kube-proxy and reaches the API through KubePrism on
`localhost:7445`. On Talos its values must set `ipam.mode=kubernetes`,
`cgroup.autoMount.enabled=false`, `cgroup.hostRoot=/sys/fs/cgroup`, drop the
`SYS_MODULE` capability, and `kubeProxyReplacement=true` with
`k8sServiceHost=localhost`, `k8sServicePort=7445`.

LoadBalancer addresses come from a `CiliumLoadBalancerIPPool` (LB-IPAM assigns
them; it is dormant until the first pool exists). Reachability is a **static
route** on the router pointing the pool prefix at the nodes — BGP was considered
and deferred as overkill for a handful of services and rare node changes, and it
is purely additive to switch on later. Keep `externalTrafficPolicy: Cluster`
unless the ingress runs as a DaemonSet, or a static route to one node plus
`Local` gives an intermittently dead service.

## Networking is dual-stack, and that is permanent

```
podSubnets     10.244.0.0/16   fd00:cbc:0::/56
serviceSubnets 10.96.0.0/12    fd00:cbc:1::/108
```

IPv4 is primary (first entry wins), IPv6 is ULA. Pod and service CIDRs, the
primary family, `dnsDomain` and `cni.name` are all effectively immutable —
changing them is a rolling rebuild of every node, so they are decided here and
not later. Dual-stack now costs nothing (IPv4 still does all egress, no NAT64)
and means a real IPv6 prefix, when one ever arrives, is added to interfaces
without a rebuild.

IPv6-only was rejected: `ghcr.io` has no AAAA on its registry endpoint and
`registry.gitlab.com` none at all, so an IPv6-only cluster cannot even pull the
images `fleet-infra` uses without standing up NAT64 + DNS64 — two single points
of failure, for no external IPv6 anyway while the uplink is v4-only.

`machine.kubelet.nodeIP.validSubnets` pins the node InternalIP to the v4 subnet,
so kubelet does not pick an address family at random on a dual-stack node.

The cluster shares `10.82.50.0/24` with everything else deliberately: a firewall
VLAN would sit at the wrong layer. Cilium masquerades all pod egress to the node
address, so a VLAN ACL could only ever express per-node rules, never
per-workload — `CiliumNetworkPolicy` egress does that properly, keyed on pod
identity, and keeps Garage on the same L2 with no router in the S3 path.

## Placement and disks

`affinity_host` steers each VM to a physical host, but the real anchor is the
host-local SR its disks sit on: a VM cannot boot where its storage is not.

| Node | Host | SR |
| --- | --- | --- |
| talos-01 | gewisvhost1 | vhost1-ssd2 |
| talos-02 | gewisvhost1 | vhost1-ssd2 |
| talos-03 | gewisvhost3 | vhost3-ssd |

Two nodes share `vhost1` for now because `vhost4` is out of space; move a node
by changing one map entry once it frees up. The pool is `vhost1`/`vhost3`/`vhost4`
— there is no `vhost2`.

Two disks per node: a 20 GiB system disk (`xvda`) and a 10 GiB Longhorn data
disk (`xvdb`), both small for testing. **The system disk cannot be grown in
place** — Talos fixes the STATE partition boundaries at install, so resizing it
later means replacing the VM (`tofu apply -replace`), cheap for a fresh node.
The Longhorn disk is the opposite: grow the VDI and its `UserVolumeConfig`
expands on the next boot. For production, 20 GiB is too small for a
control-plane node also running workloads — 100 GiB is the intended size, set
before the VM is created.

Longhorn's data disk is mounted by a `UserVolumeConfig` named `longhorn`, which
forces the mount to `/var/mnt/longhorn`; Longhorn's Helm `defaultDataPath` must
match. The disk is selected by `!system_disk` rather than a device path, so Xen
attach order cannot misroute it.

## Known follow-ups

The infrastructure is proven — the template sizes disks correctly and all three
VMs cloned to 20/10 GiB across hosts — and `config-apply` + `bootstrap` were run,
but the cluster has **not** been independently verified healthy from here: the
build host has no route into `10.82.50.0/24`. Everything below is outstanding.

- **Cilium is not installed yet.** The nodes stay `NotReady` until it is installed
  via Helm/Flux (see "The cluster has no CNI until you install one"); that install
  and confirming the nodes reach `Ready` are still to do.
- **LoadBalancer is not set up.** No `CiliumLoadBalancerIPPool` exists yet and no
  static route points a pool prefix at the nodes; LB-IPAM stays dormant until the
  first pool is created.
- **The Longhorn `UserVolumeConfig` is validated by `talosctl` but not yet seen on
  a live node.** Confirm with `talosctl get volumestatus u-longhorn` after first
  boot; the Longhorn namespace also needs
  `pod-security.kubernetes.io/enforce=privileged`.
- **Node hostnames are Talos stable auto-names, not `talos-01/02/03`.** Talos 1.13
  seeds a `HostnameConfig` with `auto: stable` that a config patch cannot cleanly
  override, and the v1alpha1 `machine.network.hostname` field is refused while that
  document exists. Pinning friendly names needs the provider's rendered config
  inspected at first apply; cosmetic, does not block the cluster.
- **The imported VDI is labelled `talos-1.13.8-nocloud-disk`.** Purely cosmetic;
  rename it in XO if the generic label bothers you.
