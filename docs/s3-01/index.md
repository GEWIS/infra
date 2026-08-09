# s3-01

An S3 server VM on XCP-ng running Garage. OpenTofu creates the VM,
nixos-anywhere installs NixOS onto it, and `nix/hosts/s3-01/garage.nix` runs a
single-node Garage cluster on the second disk.
