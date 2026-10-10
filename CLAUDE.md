# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

NixOS host configurations for GEWIS CBC, the OpenTofu that provisions them, and the
Flux tree reconciled into the Talos cluster. `README.md` covers layout and operator
workflow; `AGENTS.md` carries the docs rules, repeated below because they are enforced
by CI. **This repository is public.**

Always work in the main worktree, do not ever commit or push changes.

In comments or documentation, never reference old versions of the code or mention why specific decisions were made over other alternatives.
The docs and comments should always reflect the current state of the code, not reference old versions.

Comments in the code itself should be minimal, and should only be used if an unorthodox decision was made.
If comments explaning the code are required, your code is too complex and should be refactored.

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

The `tofu` roots need direnv. The top-level `.envrc` exports only what every root needs:
the state passphrase from `secrets/tofu.yaml`, `BAO_ADDR`, `KUBECONFIG`/`TALOSCONFIG`, and
a gitignored `.envrc.local` with the operator's Scaleway state-bucket key and XO token.
A root that needs more has its own `.envrc` that runs `source_up` and then calls
`sops_export` or `bao_jwt_export`, so a secret is only in your shell inside the root that
uses it. Each new `.envrc` needs a `direnv allow`. Without an admin SSH key in
`nix/recipients.nix` none of the sops files decrypt and `tofu` cannot open state.

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

What is very important for the docs is that they should describe the (desired) state of
the repo, not step to get there or stuff like that. So not a list of commands to run, order
that have been run, but only the end result.

## Architecture

Three independent planes share one repo: NixOS hosts (`nix/`), OpenTofu roots
(`terraform/`), and Flux (`flux/`). Nothing links them at eval time; they meet only
through secrets and the cluster.

### NixOS hosts

`flake.nix` builds each host as `host "<name>" [extraModules]`: comin, disko, impermanence
and sops-nix modules, then all of `nix/modules`, then `nix/hosts/<name>/`. Every shared
module is imported by every host and is inert until enabled under the `gewis.*` option
namespace: `gewis.admin`, `gewis.comin`, `gewis.netbird`, `gewis.persistence`,
`gewis.servicePc`, `gewis.tmpfsRoot`, `gewis.zabbixAgent`. `nix/modules/xcpng.nix` is the
exception and is imported only by XCP-ng VMs. Firewall rules for the mesh use
`config.gewis.netbird.interface`, never the literal interface name.

Adding a host touches, in order: `nix/hosts/<name>/` (enabling `gewis.tmpfsRoot` or
carrying its own `disko.nix`), an entry in `flake.nix`, its age key in
`nix/recipients.nix`, `nix run .#sops-config`, `secrets/<name>.yaml`, and a docs page plus
`nav:` entry. `docs/service-pc/install.md` is the operator version of that list.

`gewis.servicePc` (`nix/modules/service-pc/`) is the kiosk/POS desktop: GNOME auto-login
as an unprivileged user, one or more Firefox instances each at a fixed URL, extra apps,
per-workspace or per-monitor placement, NFC reader, RDP. `lib.nix` holds what the
sub-files share (the placement helper, `sessionUnit`, the `browsers` and `apps`
submodules). The module deliberately names no
applications; packages, URLs and unfree allowances live in `nix/hosts/<host>/`. The
naming is "service PC", never "desktop". Fullscreen is done by sending F11 through
ydotool, so the browser chrome stays reachable.

Hosts with `gewis.tmpfsRoot` run a tmpfs root with `/persist` (impermanence, via
`gewis.persistence`). Anything that must survive a reboot goes in `extraDirectories` or
`extraFiles`; the sops age key lives at `/persist/var/lib/sops-nix/key.txt`, and each
module persists its own state (comin's clone, NetBird's state, the RDP certificate, the ssh
host key).

root keeps bash on every host: nixos-anywhere and `nixos-rebuild --target-host` pipe POSIX
fragments through root's login shell.

### Deployment paths

- `pcgewisa`, `pcgewisb`, `pcgewisc`, `pcgewisd`, `pcgewisinfo`: comin polls
  `GEWIS/infra` `main` and switches the host. **Every push to `main` deploys**, including
  commits that touch nothing of theirs. A config that fails to evaluate just stops updates. root has no ssh,
  so there is no `nixos-rebuild --target-host` fallback.
- `s3-01`: `terraform/10_s3-01` creates the XCP-ng VM and runs nixos-anywhere via
  `terraform/modules/nixos-host`; later applies only `nixos-rebuild --switch`. Replace the
  VM resource to force a reinstall.
- Talos nodes: `terraform/10_talos-hosts`, then `terraform/20_talos-bootstrap`, then Flux.

### Secrets

`.sops.yaml` is **generated**: edit `nix/recipients.nix`, run `nix run .#sops-config`,
then `sops updatekeys` on any file whose recipients changed. CI fails if the committed
file drifts. `adminOnly` lists files readable only by admins (`tofu`, `talos`,
`sealed-secrets`, `authentik`); each host file is readable by that host's age key and by
the admins unless the host sets `adminReadable = false`. Private keys are never committed.

### OpenTofu roots

Each directory under `terraform/` is its own root with its own state object in the
Scaleway bucket `gewis-tfstate`, locked with S3 conditional writes and client-side
encrypted with the passphrase from `secrets/tofu.yaml`. The object is the `key` in the
root's `backend.tf`, and it does **not** follow the directory name: it has no numeric
prefix and is sometimes shorter (`10_talos-hosts` → `talos/terraform.tfstate`,
`40_openbao-config` → `openbao/terraform.tfstate`). Never edit a key to match a
directory; tofu would start from empty state and plan to recreate everything. Roots never
read each other's state; they share data only through their `.envrc` variables and the
kubeconfig.

The two-digit prefix is the apply order on a fresh setup: lower first, roots with the
same prefix are independent of each other. Prefixes step by 10 so a new stage takes a
free number in a gap instead of renumbering. A stage that is not a root, like
`30_flux` (Flux reconciles `flux/`), is an empty directory holding a `.gitkeep`.

- `10_talos-hosts`: VMs, machine config, etcd bootstrap. Talks to node IPs on
  `10.82.50.0/24`, so it needs the on-site LAN or VPN. `10_s3-01` runs alongside it.
- `20_talos-bootstrap`: Cilium, the Gateway API CRDs, the `sealed-secrets` namespace with a
  pinned sealing key, and the Flux Operator with its `FluxInstance`. Uses `.kube/config`,
  which `mint-creds` writes on demand and which expires after one hour.
- `40_*`, `50_*`, `60_grafana-config`: configure services now running in the cluster.
  The roots with a vault provider (`40_*`, `50_*`) need `TF_VAR_bao_jwt`, which their
  `.envrc` takes from a live `kubectl`. authentik cannot start before
  `40_databases` creates its database, `50_authentik-config` configures the
  `auth/oidc` mount `40_openbao-config` creates, `50_ssh-certificates` configures its
  `ssh` mount, and Grafana mounts the OIDC Secret `50_authentik-config` writes.

`terraform/modules/xcpng-vm` and `nixos-host` are the shared building blocks.

### Flux layers

One `Kustomization` per layer in `flux/clusters/gewis-prod/`, each with `wait: true`:

```
sealed-secrets → controllers → config ─┬→ services → apps
                                       └→ openbao ──┘
```

`controllers` holds operators (cert-manager, external-dns, longhorn, external-secrets,
cloudnative-pg, mariadb-operator), `config` their cluster-wide objects (issuers, Gateway, storage classes,
Corefile), `services` things others consume (resolver, Postgres, MariaDB, node exporter), `apps` the
consumers (authentik, LGTM, Kite, Hubble). Put new things in the layer matching that split.
SealedSecrets sit next to the chart that uses them, but never in a layer that depends on
the layer consuming them, or the deploy deadlocks. `docs/cluster/layers.md` explains
why each edge exists.

Each layer's directory is `flux/<prefix>_<name>`, with the same two-digit rule as the
OpenTofu roots: lower reconciles first, equal prefixes are independent. The prefix follows
`dependsOn`, it does not drive it. The `Kustomization` names carry no prefix; never rename
one, because its parent prunes the old object and that deletes everything it applied.

Renovate automerges minor and patch bumps across `flux/` and pinned versions in
`terraform/`.
