# Secrets

`secrets/pcgewisinfo.yaml` is encrypted to the host's age key and to every
admin in `nix/recipients.nix`, so it can be edited from any admin's machine:

```sh
sops secrets/pcgewisinfo.yaml
```

Adding or removing a recipient goes through `nix/recipients.nix`,
`nix run .#sops-config` and `sops updatekeys secrets/pcgewisinfo.yaml`.

| Secret | Use |
| --- | --- |
| `kioskUrl` | Page the kiosk opens; owned by `gewis` |
| `rdpPassword` | Password for [remote access](../service-pc/remote.md); owned by `gewis` |
| `cbcPassword` | Hashed password for `cbc`; `neededForUsers` |
| `netbird-setupkey` | Setup key the NetBird client enrols with |
