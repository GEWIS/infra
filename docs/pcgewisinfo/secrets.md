# Secrets

`secrets/pcgewisinfo.yaml`, encrypted to the host key only, so it can currently
be read and edited only from the host itself.

That is a gap rather than a decision. Adding an admin as a recipient needs the
host's key, because `sops updatekeys` decrypts before it re-encrypts. From the
host, with `/persist/var/lib/sops-nix/key.txt` available:

```sh
SOPS_AGE_KEY_FILE=/persist/var/lib/sops-nix/key.txt \
  sops updatekeys secrets/pcgewisinfo.yaml
```

Add `admin_luuk` back to this file's rule in `.sops.yaml` first, or the re-key
is a no-op.

| Secret | Use |
| --- | --- |
| `kioskUrl` | Page the kiosk opens; owned by `gewis` |
| `cbcPassword` | Hashed password for `cbc`; `neededForUsers` |
