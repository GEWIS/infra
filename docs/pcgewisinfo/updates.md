# Updates

`nix/hosts/pcgewisinfo/comin.nix` points comin at
`https://github.com/GEWIS/infra.git`, branch `main`. comin polls that
repo and switches the host, so **pushing to `main` deploys** — including commits
that only touch `s3-01`. A configuration that fails to evaluate simply stops
updates; the running system is untouched.

There is no `nixos-rebuild --target-host` path here: root has no ssh access
(`PermitRootLogin = "no"`).
