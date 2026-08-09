# First-time setup

1. **Generate the host age key** and put its public half in `.sops.yaml` as
   `&s3_01`:

   ```sh
   age-keygen -o s3-01-age.key
   age-keygen -y s3-01-age.key
   ```

   `.envrc.local` reads the private key into `TF_VAR_host_age_key`, which
   `terraform/s3-01/extra-files.sh` writes to `/var/lib/sops-nix/key.txt` on the target
   so sops-nix can decrypt on first boot.

2. **Mint a NetBird setup key** at [nb.gewis.nl](https://nb.gewis.nl) with
   *Allow extra DNS labels* enabled — `gewis.netbird.dnsLabel` is refused
   without it — and store it:

   ```sh
   sops secrets/s3-01.yaml     # netbird-setupkey: <setup key>
   ```

3. **Arrange reachability, deliberately outside OpenTofu.** tofu discovers the
   address but does nothing to make it routable from where you apply. Reach it
   directly if you run on-prem, or through a NetBird routing peer. One way: add
   the subnet as a resource in the GEWIS NetBird network (dashboard →
   *Networks*):

   ```
   s3 server    10.82.50.0/24
   ```

   A subnet beats a `/32` precisely because the address is discovered rather
   than pinned. Check every octet — a wrong one routes silently into nowhere and
   looks exactly like a dead host. Verify with `ip route get <address>`, which
   must report `dev nb-nbg` and not your WAN interface.

   Jump hosts belong in `~/.ssh/config`, not in this repo; nixos-anywhere honours
   it because it does not pass `-F none` to ssh.

   ```sshconfig
   Match host 10.82.50.*
     ProxyJump cbclocal@swarm203
     User root
     StrictHostKeyChecking accept-new
   ```

4. **Track new files in git** before building — including `secrets/s3-01.yaml`,
   which is created last and is the one people forget.
