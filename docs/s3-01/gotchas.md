# Gotchas

- **The address is pinned to `10.82.50.100`**, arranged outside this repo, so
  nothing here declares or enforces it. Before it was pinned the address moved
  between the bootstrap OS and the installed system, because `dhclient` and
  systemd-networkd identify differently to the DHCP server and got different
  leases. `dhcpV4Config.ClientIdentifier = "mac"` was tried as a fix and **did
  not work**; it is removed, do not re-add it. Nothing depends on the address
  holding still either way — `target_host` is read live from the guest agent and
  is in no trigger, so churn can never force a reinstall.
- **A rebuild can drop its own connection.** Activation restarts
  `systemd-networkd`, which can renew onto a *different* lease mid-apply. The
  switch itself completes — you will see `activating the configuration...` and
  the unit restart list — and then the deploy dies with
  `Timeout, server <old-ip> not responding` and `exit 255`. Observed going from
  `.100` to `.102`. The host is fine; only tofu's bookkeeping is unfinished.
  Confirm with `readlink -f /run/current-system` on the new address, then re-run
  `tofu apply`: it re-reads the address from the guest agent, and re-running the
  switch on an already-switched host is a fast no-op.
- **The host answers on the mesh too.** NetBird gives it a name from its
  hostname (`s3-01`, `s3-01.net.nb.gewis.nl`) even though
  `NB_EXTRA_DNS_LABELS` is unset, and that address does not move with DHCP. It
  is the better target when chasing a host whose lease just changed — though it
  takes a moment to come back after `netbird-gewis.service` restarts.
- **`wss://`, not `https://`** for the XO endpoint. The wrong scheme, or a
  self-signed cert without `XOA_INSECURE=true`, gives `websocket: bad handshake`.
- **Sizes are in bytes** in the provider; this config takes GiB and converts.
- **A template is required** — the VM cannot boot bare. The guest agent goes in
  via cloud-init, which only fires on first boot, so recreate the VM if you change
  cloud-init. A reboot will not re-run it.
- **`net.ifnames=0` is what makes IP discovery work.** Ubuntu noble's
  `xe-guest-utilities` is pinned at 7.20.2, whose `vifNamePrefixList` is
  `{eth, eno, ens, emp, enx}`. It lacks `enX`, exactly the name Xen assigns on
  24.04, so the agent runs fine (XO shows `managementAgentDetected: true`) but
  never writes `attr/vif/*/ipv4/*` to xenstore. XAPI has no host-side IP discovery
  to fall back on, so `expected_ip_cidr` would never be satisfied and create would
  die at the timeout. Cloud-init works around it by dropping `net.ifnames=0` into
  `/etc/default/grub.d/`, running `update-grub` and rebooting; the NIC then comes
  up as `eth0`, which 7.20.2 does parse. **Do not remove that reboot** — the
  kernel parameter only takes effect on the next boot. See
  [xcp-ng/xcp#655](https://github.com/xcp-ng/xcp/issues/655) and
  [xe-guest-utilities#164](https://github.com/xenserver/xe-guest-utilities/issues/164).
  This affects only the throwaway bootstrap Ubuntu; nixpkgs ships 10.0.1, which
  does include `enX`.
- **20-minute create timeout** in `modules/xcpng-vm/main.tf`, because a full
  clone is genuinely slow and can overrun the provider's 5-minute default.
- **NetBird runs unhardened** (`nix/modules/netbird.nix`): its built-in SSH
  server has to switch into the login user, which the hardened systemd sandbox
  blocks.
- **Rotating the setup key changes nothing on a joined host.** The peer is
  identified by the WireGuard key in `/var/lib/netbird-gewis/config.json`, and
  the client only puts a setup key on the wire when management reports the peer
  as unregistered. `netbird-gewis-login.service` reinforces this: it runs
  `netbird up` only while `netbird status` says `NeedsLogin`. So a new key with
  *Allow extra DNS labels* does not grant the existing peer that permission —
  `allow_extra_dns_labels` is stamped onto the peer record at registration and
  never re-derived, and `ExtraDNSLabels` is not updatable by login, sync, or the
  management API. Adding `dnsLabel` to a peer registered without the flag makes
  its next login fail with `setup key doesn't allow extra DNS labels`. Delete
  the peer in the dashboard first, then restart the login unit.
- **State lives in Scaleway**, encrypted before it leaves your machine — see
  *State* above. Never move it onto the S3 server this project creates.
