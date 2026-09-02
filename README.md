# CBC infra

NixOS host configurations for GEWIS CBC, plus the OpenTofu that provisions them.

## Hosts

| Host | Role | Provisioned by | Updated by |
| --- | --- | --- | --- |
| `pcgewisinfo` | Info-screen kiosk; also DHCP and print server for the booth LAN | Installed by hand | comin, polling `main` |
| `s3-01` | Garage S3 object store, single node | OpenTofu + nixos-anywhere | `tofu apply` |
| `talos-01`..`03` | 3-node Talos Kubernetes cluster | OpenTofu + Image Factory | `tofu apply` (talos root) |

The docs are published as a browsable site at
<https://gewis.github.io/infra/>, built from `docs/` on every push to
`main`. Operational detail lives in [`docs/pcgewisinfo/`](docs/pcgewisinfo/index.md),
[`docs/s3-01/`](docs/s3-01/index.md) and [`docs/talos/`](docs/talos/index.md). What runs
*inside* the Kubernetes cluster — Flux layering, ingress, certificates, DNS,
OpenBao — is [`docs/cluster/`](docs/cluster/index.md). S3 buckets and the
credentials the cluster reads for them are
[`docs/garage-buckets/`](docs/garage-buckets/index.md); the LGTM stack and its
tenancy model are [`docs/observability/`](docs/observability/index.md). HA Postgres
and MariaDB placement and their backup model are
[`docs/databases/`](docs/databases/index.md).

## Layout

```
flake.nix              nixosConfigurations + devShell
nix/modules/           shared NixOS modules
nix/hosts/<host>/      per-host configuration
secrets/<host>.yaml    sops-encrypted secrets, one file per host
terraform/modules/          shared modules (xcpng-vm, nixos-host)
terraform/s3-01/            OpenTofu root: XCP-ng VM + nixos-anywhere (s3-01)
terraform/talos-hosts/      OpenTofu root: 3-node Talos cluster
terraform/talos-bootstrap/  OpenTofu root: in-cluster bootstrap (Cilium, sealed-secrets, Flux)
terraform/openbao-config/   OpenTofu root: OpenBao mounts and secrets
terraform/garage-buckets/   OpenTofu root: Garage buckets + their credentials in OpenBao
terraform/grafana-config/   OpenTofu root: Grafana organizations and datasources
terraform/postgres-databases/ OpenTofu root: Postgres roles + their credentials in OpenBao
terraform/authentik-config/ OpenTofu root: authentik's AD source, providers and applications
flux/                  Flux GitOps tree, reconciled into the cluster
docs/                  per-host and cluster operational detail
```

## Shared modules

`nix/modules` is imported by every host and pulls in:

| Module | Contents |
| --- | --- |
| `common.nix` | Flakes, weekly GC, timezone, immutable users, sshd defaults, firewall on |
| `shell.nix` | zsh as the default user shell, the prompt theme, the base tool set |
| `netbird.nix` | `gewis.netbird.*` — GEWIS mesh client, off unless a host enables it |
| `service-pc.nix` | `gewis.servicePc.*` — GNOME session, pinned apps and RDP for service PCs, off unless a host enables it |

`xcpng.nix` sits alongside them but is imported only by hosts that run on
XCP-ng, because it carries Xen-specific boot and network settings.

Anything a host needs that the other one does not — the kiosk's printers, the
S3 box's disk layout — stays in `nix/hosts/<host>/`.

## Shell

Normal users get zsh, with completion, autosuggestions, syntax highlighting and
a two-line prompt showing user, host, path, git state, an exit code when the
last command failed, and a `nix` marker inside a dev shell. Commands over one
second get their duration on the right.

**root deliberately keeps bash.** `nixos-anywhere` and `nixos-rebuild
--target-host` pipe POSIX shell fragments over ssh and run them through root's
login shell, so root's shell stays a plain POSIX-compatible bash.

## Working on the repo

```sh
direnv allow      # or: nix develop
```

That provides `opentofu`, `nixos-anywhere`, `sops`, `age`, `ssh-to-age`,
`talosctl`, `kubectl`, `nixfmt` and `jq`. Format with `nix fmt` before
committing.

Flakes only see git-tracked files, so `git add` new files before building or
running `tofu plan`; an untracked file is invisible to the build even though it
is plainly on disk.

## Secrets

One sops file per host in `secrets/`, plus `secrets/tofu.yaml` for the state
encryption passphrase. Recipients are declared in `.sops.yaml`, where the
`admins` group is the one to extend when someone else needs access.

```sh
sops secrets/s3-01.yaml
sops secrets/pcgewisinfo.yaml
sops secrets/tofu.yaml
sops secrets/talos.yaml
```

Private age keys are never committed — `.gitignore` covers `*-age.key` and
`key.txt`. **This repository is public**, so everything in `secrets/` is
published as ciphertext.

## Deploying

`pcgewisinfo` — push to `main`; comin polls the repo and switches the host.
Every push rebuilds it, including commits that only touch `s3-01`.

Both live under `terraform/`, each its own root with its own state, so an apply
to one cannot touch the other. `s3-01` — see [`docs/s3-01.md`](docs/s3-01.md):

```sh
cd terraform/s3-01 && tofu apply
```

`talos-*` — see [`docs/talos.md`](docs/talos.md); a Talos template must be
imported into Xen Orchestra once first, then:

```sh
cd terraform/talos-hosts && tofu apply
```

OpenTofu state is remote, in Scaleway Object Storage, locked with native S3
conditional writes and encrypted client-side. Every operator uses their own
Scaleway API key in a gitignored `.envrc.local`; access is granted by IAM on a
dedicated Project, so offboarding is revoking one key and nothing shared gets
rotated. The encryption passphrase comes from `secrets/tofu.yaml` via `.envrc`
and is not an access credential.
