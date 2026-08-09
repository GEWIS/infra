# Prerequisites

1. Xen Orchestra reachable from wherever you run OpenTofu.
2. An XO auth token: XO web UI → your user (bottom-left) → *Authentication
   tokens*.
3. A working guest agent in the bootstrap OS. The address is **discovered**, not
   declared: the provider blocks during create until the agent reports an IPv4
   inside `expected_ip_cidr`, then hands it to nixos-anywhere. A broken agent
   means the create times out at 20 minutes.
