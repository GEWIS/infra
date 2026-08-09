# VM memory must be static, not ballooned

`xcpng-vm` sets `memory_min = memory_max`. Leave `memory_min` unset and the
provider writes `dynamic = [0, memory_max]`, which switches on XCP-ng Dynamic
Memory Control: when the host is overcommitted, its scheduler squeezes every
guest toward its dynamic minimum and the balloon driver returns the pages from
inside the guest. `MemTotal` drops and Kubernetes just sees a smaller node.

That is backwards for a cluster node. Ballooning reacts to *host* pressure and
is blind to in-guest demand, so a node that is OOM-killing pods gets nothing
back. One node sat at 2 GiB of its nominal 8 GiB this way: kubelet missed
heartbeats, the node flapped `NotReady`, containerd tore down sandboxes, and the
visible symptom was Longhorn pods crash-looping — the storage layer was fine.
Static memory reserves the full amount on the host and cannot be squeezed.
