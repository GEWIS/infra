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

## The image is a manual prerequisite

The provider can clone a template but cannot build one — `template` is
`Required` and forces replacement, and there is no way to attach an uploaded
disk as a VM's boot disk. So the Talos image becomes a template **by hand,
once**. Talos upgrades afterwards go through `talosctl upgrade`, never a
re-import.

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

To create the template:

```sh
curl -LO "https://factory.talos.dev/image/544579955b64479597e31a593d522bfa8c9ce21939264e852e54c55e11b4d788/v1.13.8/nocloud-amd64.raw.xz"
unxz nocloud-amd64.raw.xz
nix shell nixpkgs#qemu -c qemu-img convert -f raw -O vpc nocloud-amd64.raw talos-1.13.8-nocloud.vhd
```

Xen Orchestra imports VHD/VMDK, not raw, hence the `qemu-img` step. Then in XO:
**Import → Disk** onto an SR; **New VM** with **Boot firmware = UEFI** (no Secure
Boot) and no meaningful disk/CPU (tofu overrides those per clone); attach the
imported VDI as position 0 and drop the wizard's throwaway disk; **Convert to
template** without booting it, named exactly `talos-1.13.8-nocloud`. Rename the
`template_name_label` local if you name it something else.

The VHD is ~4 GiB virtual; a full clone resizes the system disk to 20 GiB and
Talos grows its EPHEMERAL partition into the space on first boot.

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

```sh
cd terraform/talos
tofu init
tofu plan
tofu apply
```

Each node boots the nocloud image with no config source and sits in maintenance
mode on its reserved address. tofu then pushes the machine configuration over
the API; the node writes it and reboots into the configured system;
`talos_machine_bootstrap` runs etcd genesis on `talos-01` only.

A first apply can race a node reaching maintenance mode — a config-apply that
errors with a connection failure just means the node was not up yet. Re-run;
every step is idempotent.

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

- **Node hostnames are Talos stable auto-names, not `talos-01/02/03`.** Talos
  1.13 seeds a `HostnameConfig` with `auto: stable` that a config patch cannot
  cleanly override, and the v1alpha1 `machine.network.hostname` field is refused
  while that document exists. Pinning friendly names needs the provider's
  rendered config inspected at first apply; it is cosmetic and does not block the
  cluster.
- **The Longhorn `UserVolumeConfig` is validated by `talosctl` but not yet on a
  live node.** Confirm with `talosctl get volumestatus u-longhorn` after first
  boot.
