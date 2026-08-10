# The cluster has no CNI until you install one

`cluster.network.cni.name = none` and `cluster.proxy.disabled = true`: Talos
ships neither Flannel nor kube-proxy here. After bootstrap the nodes stay
`NotReady` until Cilium is installed, which is a Helm/Flux concern, not tofu.
Cilium replaces kube-proxy and reaches the API through KubePrism on
`localhost:7445`. On Talos its values must set `ipam.mode=kubernetes`,
`cgroup.autoMount.enabled=false`, `cgroup.hostRoot=/sys/fs/cgroup`, drop the
`SYS_MODULE` capability, and `kubeProxyReplacement=true` with
`k8sServiceHost=localhost`, `k8sServicePort=7445`.

Pod-to-pod traffic is encrypted with **WireGuard** (`encryption.enabled=true`,
`encryption.type=wireguard`). Talos ships WireGuard in-kernel and the agent
already holds `NET_ADMIN`, so this needs no extra capability or kernel module.

The same release also carries the Gateway API implementation
(`gatewayAPI.enabled=true`) and the values that expose it on the host network —
see [Ingress](ingress.md).
