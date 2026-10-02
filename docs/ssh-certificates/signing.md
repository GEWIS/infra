# Signing and logging in

The dev shell has `ssh-login`:

```sh
ssh-login                      # signs ~/.ssh/id_ed25519.pub
ssh-login ~/.ssh/id_work       # or another key, by its private key path
ssh root@10.82.50.100
```

It opens the browser for `bao login -method=oidc` only when the current token cannot
sign, so within the token's hour a re-sign is silent. It then signs the public key
for both `root` and `cbc`, writes `<key>-cert.pub` next to the key, and prints the
certificate. `ssh` offers `<key>-cert.pub` alongside `<key>` on its own; no config,
no agent. The certificate is the public key plus principals, key ID and validity,
stamped by the CA — the host still makes you prove the private key, so the file is
useless on its own. An expired one is left in place and overwritten next time.

It never runs on its own: an automatic run would mean a browser login at random
moments. Outside the dev shell, the same by hand:

```sh
bao login -method=oidc
bao write -field=signed_key ssh/sign/admin \
  public_key=@$HOME/.ssh/id_ed25519.pub valid_principals=root,cbc \
  > ~/.ssh/id_ed25519-cert.pub
```

## Over the mesh or the LAN

Every host with `gewis.netbird.enable` also sets `ServerSSHAllowed`, so NetBird runs
its own SSH server for peers. A connection to the host's **LAN address** reaches
sshd and the certificate path above. Whether a connection over the **mesh** (the
`nb-*` interface, the host's NetBird name) reaches sshd or NetBird's server depends on
the NetBird version and client, and NetBird's server knows nothing about this CA.
Test both paths before relying on the mesh one; this is also why the service PCs,
which are mostly reached over the mesh, do not enable it yet.
