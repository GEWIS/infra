# talos

A three-node Talos Linux Kubernetes cluster on XCP-ng, one node per physical
host. OpenTofu creates the VMs and hands each one its machine configuration over
the Talos API; there is no SSH and no nixos-anywhere here.
