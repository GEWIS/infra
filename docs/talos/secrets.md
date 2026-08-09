# Secrets never reach the state

`talos_machine_secrets` would write five CA private keys, the bootstrap token
and the etcd encryption secrets into the state file. Instead the PKI is minted
once with `talosctl gen secrets`, stored sops-encrypted in `secrets/talos.yaml`,
and decrypted by `.envrc` into `TF_VAR_talos_secrets`. `main.tf` remaps its keys
into the shape the provider wants and feeds it only through `ephemeral` blocks
and write-only (`*_wo`) inputs. The state holds resource ids, node addresses and
a non-secret `machine_configuration_hash` — nothing else. That hash is how the
provider detects config drift without persisting the config: write-only values
are still present during a run, just never written down.

The provider's `ephemeral talos_machine_secrets` is not an alternative — it has
no seed input, so every open mints fresh CAs and would orphan a running cluster.

## kubeconfig and talosconfig

Generated locally from the same sops bundle, never through tofu, so no admin
credential lands in state either:

```sh
sops -d secrets/talos.yaml > /tmp/talos-secrets.yaml
talosctl gen config gewis https://kube.gewis.nl:6443 \
  --with-secrets /tmp/talos-secrets.yaml --output-types talosconfig -o talosconfig
talosctl --talosconfig talosconfig --nodes 10.82.50.101 kubeconfig
rm /tmp/talos-secrets.yaml
```

`kube.gewis.nl` is the Kubernetes API endpoint only — A records to all three
nodes on `:6443` — and belongs in the kubeconfig. For `talosctl`, use the
**node IPs** as endpoints: the Talos apid certificate (from `certs.os`) does not
carry `kube.gewis.nl` in its SANs unless it is added to `machine.certSANs`.
