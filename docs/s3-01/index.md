# s3-01

An S3 server VM on XCP-ng running SeaweedFS. OpenTofu creates the VM,
nixos-anywhere installs NixOS onto it, and `nix/hosts/s3-01/seaweedfs.nix` runs
a single `weed server` process — master, volume, filer and S3 in one unit — on
the second disk. The S3 API and its AWS-compatible IAM API share port `8333`,
the only port open in the firewall.
