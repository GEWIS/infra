# CBC infra

NixOS host configurations for GEWIS CBC, plus the OpenTofu that provisions them.

## Hosts

| Host | Role | Provisioned by | Updated by |
| --- | --- | --- | --- |
| `pcgewisinfo` | Info-screen kiosk; also DHCP and print server for the booth LAN | Installed by hand | comin, polling `main` |
| `s3-01` | Garage S3 object store, single node | OpenTofu + nixos-anywhere | `tofu apply` |

Operational detail lives in [`docs/pcgewisinfo.md`](docs/pcgewisinfo.md) and
[`docs/s3-01.md`](docs/s3-01.md).

## Layout

```
flake.nix              nixosConfigurations + devShell
nix/modules/           shared NixOS modules
nix/hosts/<host>/      per-host configuration
secrets/<host>.yaml    sops-encrypted secrets, one file per host
terraform/             OpenTofu: XCP-ng VM + nixos-anywhere (s3-01 only)
docs/                  per-host operational detail
```

## Shared modules

`nix/modules` is imported by every host and pulls in:

| Module | Contents |
| --- | --- |
| `common.nix` | Flakes, weekly GC, timezone, immutable users, sshd defaults, firewall on |
| `shell.nix` | fish as the default user shell, the prompt theme, the base tool set |
| `netbird.nix` | `gewis.netbird.*` — GEWIS mesh client, off unless a host enables it |

`xcpng.nix` sits alongside them but is imported only by hosts that run on
XCP-ng, because it carries Xen-specific boot and network settings.

Anything a host needs that the other one does not — the kiosk's printers, the
S3 box's disk layout — stays in `nix/hosts/<host>/`.

## Shell

Normal users get fish, with a two-line prompt showing user, host, path, git
state, an exit code when the last command failed, and a `nix` marker inside a
dev shell. Commands over one second get their duration on the right.

**root deliberately keeps bash.** `nixos-anywhere` and `nixos-rebuild
--target-host` pipe POSIX shell fragments over ssh and run them through root's
login shell; fish cannot parse those, so deploys to `s3-01` would break.

## Working on the repo

```sh
direnv allow      # or: nix develop
```

That provides `opentofu`, `nixos-anywhere`, `sops`, `age`, `ssh-to-age`,
`nixfmt` and `jq`. Format with `nix fmt` before committing.

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
```

Private age keys are never committed — `.gitignore` covers `*-age.key` and
`key.txt`. **This repository is public**, so everything in `secrets/` is
published as ciphertext.

## Deploying

`pcgewisinfo` — push to `main`; comin polls the repo and switches the host.
Every push rebuilds it, including commits that only touch `s3-01`.

`s3-01` — see [`docs/s3-01.md`](docs/s3-01.md):

```sh
cd terraform && tofu apply
```

OpenTofu state is remote, in Scaleway Object Storage, locked with native S3
conditional writes and encrypted client-side. Every operator uses their own
Scaleway API key in a gitignored `.envrc.local`; access is granted by IAM on a
dedicated Project, so offboarding is revoking one key and nothing shared gets
rotated. The encryption passphrase comes from `secrets/tofu.yaml` via `.envrc`
and is not an access credential.
