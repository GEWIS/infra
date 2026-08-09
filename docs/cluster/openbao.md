# OpenBao

Three-replica Raft, sealed with a static key from a SealedSecret and reached at
`https://openbao.cbc.gewis.nl:8443`.

It self-initialises. Auto-unseal cannot unseal a barrier that was never
initialised, and a StatefulSet will not start pod 1 until pod 0 is `Ready`, so an
uninitialised OpenBao deadlocks at pod 0. The `initialize` stanza breaks that on
first boot, and it only runs against **empty storage** — a partially-initialised
PVC has to be deleted for it to re-run.

Self-init requests take flat values only; a nested map is rejected as `invalid
request`, and a failed request is fatal to the process. The root token is created
and immediately revoked, so the stanza must also provision a way in — here the
Kubernetes auth method bound to the `openbao-admin` ServiceAccount, which avoids
storing an admin password anywhere:

```sh
bao write auth/kubernetes/login role=admin \
  jwt="$(kubectl -n openbao create token openbao-admin)"
```

`.envrc` exports that token as `TF_VAR_bao_jwt` for the `openbao-config` root,
failing quietly when the cluster is unreachable.

`disable_mlock` is not a valid OpenBao 2.x option; it was removed and is only
warned about, not rejected.
