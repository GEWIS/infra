# s3-01

An S3 server VM on XCP-ng running SeaweedFS. OpenTofu creates the VM,
nixos-anywhere installs NixOS onto it, and `nix/hosts/s3-01/seaweedfs.nix` runs
a single `weed server` process — master, volume, filer and S3 in one unit — on
the second disk. The S3 API and its AWS-compatible IAM API share port `8333`,
the only port open in the firewall.

Day to day, root logs in with [SSH certificates](../ssh-certificates/index.md)
signed by OpenBao. The only authorized key is a shared break-glass key whose
private half lives in the password manager; use it when OpenBao or authentik is
down. It is also the key `terraform/10_s3-01` installs with, so a reinstall
needs it loaded in your SSH agent. Rotating it means changing it in both
`terraform/10_s3-01/main.tf` and `nix/hosts/s3-01/default.nix` and applying.
