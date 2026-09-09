# CLAUDE.md

Always work in the main worktree, do not ever commit or push changes.

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

NixOS host configurations for GEWIS CBC, the OpenTofu that provisions them, and the
Flux tree reconciled into the Talos cluster. `README.md` covers layout and operator
workflow; `AGENTS.md` carries the docs rules, repeated below because they are enforced
by CI. **This repository is public.**

## Commands

```sh
direnv allow                 # or: nix develop — tofu, sops, talosctl, kubectl, nixfmt, mkdocs, ...
nix fmt                      # nixfmt; run before committing
nix flake check              # what CI runs: sops-config sync + every host evaluates + service-pc VM test
nix build .#nixosConfigurations.<host>.config.system.build.toplevel   # one host, no VM test
nix build .#checks.x86_64-linux.service-pc                             # the GNOME/RDP VM test alone
nix build .#checks.x86_64-linux.service-pc.driverInteractive           # then ./result/bin/nixos-test-driver
nix build .#docs             # mkdocs --strict: fails on broken links or pages missing from nav
mkdocs serve                 # live preview of docs/
nix run .#sops-config        # regenerate .sops.yaml from nix/recipients.nix
sops secrets/<name>.yaml     # edit a secrets file
cd terraform/<root> && tofu init && tofu plan && tofu apply
```

Flakes only see git-tracked files: `git add` a new file before `nix build`, `nix flake
check` or `tofu plan`, or it is invisible to the build.

The `tofu` roots need `.envrc`: it decrypts `secrets/*.yaml` into `TF_VAR_*`, mints
`.talos/config` and `.kube/config` from `secrets/talos.yaml` via `mint-creds`, and
sources a gitignored `.envrc.local` for the operator's Scaleway state-bucket key. Without
a private age key in `.sops.yaml`'s admin group none of that works and `tofu` cannot
open state.

Commits use conventional prefixes (`feat:`, `fix:`, `chore:`, `refactor:`, `ci:`, `test:`).

## Docs are part of every change

`docs/` is published to <https://gewis.github.io/infra/> from `main`. When behaviour,
paths, commands, addresses or secrets change, fix every page that mentions them (grep
`docs/` for the old value). New host, service, OpenTofu root or Flux layer: add a page and
list it under `nav:` in `mkdocs.yml`. Removed thing: delete both. Relative links only.
`docs/service-pc/options.md` is a hand-written table of `gewis.servicePc` options and
must be edited alongside `nix/modules/service-pc/options.nix`.

In your reply, always say whether the docs needed a change and what you did, even when
the answer is "no docs change needed".

## Architecture

Three independent planes share one repo: NixOS hosts (`nix/`), OpenTofu roots
(`terraform/`), and Flux (`flux/`). Nothing links them at eval time; they meet only
through secrets and the cluster.

### NixOS hosts

`flake.nix` builds each host as `host "<name>" [extraModules]`: comin, disko, impermanence
and sops-nix modules, then all of `nix/modules`, then `nix/hosts/<name>/`. Every shared
module is imported by every host and is inert until enabled under the `gewis.*` option
namespace: `gewis.comin`, `gewis.persistence`, `gewis.netbird`, `gewis.servicePc`.
`nix/modules/xcpng.nix` is the exception and is imported only by XCP-ng VMs.

Adding a host touches, in order: `nix/hosts/<name>/` (with `disko.nix`), an entry in
`flake.nix`, its age key in `nix/recipients.nix`, `nix run .#sops-config`,
`secrets/<name>.yaml`, and a docs page plus `nav:` entry.

`gewis.servicePc` (`nix/modules/service-pc/`) is the kiosk/POS desktop: GNOME auto-login
as an unprivileged user, Firefox at a fixed URL, extra apps, per-workspace or per-monitor
placement, NFC reader, RDP. `lib.nix` holds what the sub-files share (the placement
helper, `sessionUnit`, the `apps` submodule). The module deliberately names no
applications; packages, URLs and unfree allowances live in `nix/hosts/<host>/`. The
naming is "service PC", never "desktop". Fullscreen is done by sending F11 through
ydotool rather than Firefox's `--kiosk`, on purpose, so the browser chrome stays reachable.

Hosts with `gewis.persistence` run a tmpfs root with `/persist` (impermanence). Anything
that must survive a reboot goes in `extraDirectories`; the sops age key lives at
`/persist/var/lib/sops-nix/key.txt`, and comin's clone is persisted by `comin.nix` itself.

root keeps bash on every host: nixos-anywhere and `nixos-rebuild --target-host` pipe POSIX
fragments through root's login shell.

### Deployment paths

- `pcgewisc`, `pcgewisd`, `pcgewisinfo`: comin polls `GEWIS/infra` `main` and switches
  the host. **Every push to `main` deploys**, including commits that touch nothing of
  theirs. A config that fails to evaluate just stops updates. root has no ssh, so there is
  no `nixos-rebuild --target-host` fallback.
- `s3-01`: `terraform/s3-01` creates the XCP-ng VM and runs nixos-anywhere via
  `terraform/modules/nixos-host`; later applies only `nixos-rebuild --switch`. Replace the
  VM resource to force a reinstall.
- Talos nodes: `terraform/talos-hosts`, then `terraform/talos-bootstrap`, then Flux.

### Secrets

`.sops.yaml` is **generated**: edit `nix/recipients.nix`, run `nix run .#sops-config`,
then `sops updatekeys` on any file whose recipients changed. CI fails if the committed
file drifts. `adminOnly` lists files readable only by admins (`tofu`, `talos`,
`sealed-secrets`, `authentik`); each host file is readable by that host's age key and by
the admins unless the host sets `adminReadable = false`. Private keys are never committed.

### OpenTofu roots

Each directory under `terraform/` is its own root with its own state object in the
Scaleway bucket `gewis-tfstate` (`<root>/terraform.tfstate`), locked with S3 conditional
writes and client-side encrypted with the passphrase from `secrets/tofu.yaml`. Roots never
read each other's state; they share data only through `.envrc` variables and the minted
kubeconfig. Effective order on a fresh cluster:

1. `talos-hosts`: VMs, machine config, etcd bootstrap. Talks to node IPs on
   `10.82.50.0/24`, so it needs the on-site LAN or VPN.
2. `talos-bootstrap`: Cilium, the Gateway API CRDs, the `sealed-secrets` namespace with a
   pinned sealing key, and Flux. Uses `.kube/config`.
3. Flux reconciles `flux/`.
4. `openbao-config`, `garage-buckets`, `postgres-databases`, `grafana-config`,
   `authentik-config`: configure services now running in the cluster. They need
   `BAO_ADDR` and `TF_VAR_bao_jwt`, which `.envrc` takes from a live `kubectl`.

`terraform/modules/xcpng-vm` and `nixos-host` are the shared building blocks.

### Flux layers

One `Kustomization` per layer in `flux/clusters/gewis-prod/`, each with `wait: true`:

```
sealed-secrets → controllers → config ─┬→ services → apps
                                       └→ openbao ──┘
```

`controllers` holds operators (cert-manager, external-dns, longhorn, external-secrets,
cloudnative-pg), `config` their cluster-wide objects (issuers, Gateway, storage classes,
Corefile), `services` things others consume (resolver, Postgres, node exporter), `apps` the
consumers (authentik, LGTM, Hubble). Put new things in the layer matching that split.
SealedSecrets sit next to the chart that uses them, but never in a layer that depends on
the layer consuming them, or the deploy deadlocks. `docs/cluster/layers.md` explains
why each edge exists.

Renovate automerges minor and patch bumps across `flux/` and pinned versions in
`terraform/`.
