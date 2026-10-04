# OpenBao

Single-replica Raft, sealed with a static key from a SealedSecret and reached at
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

The `.envrc` of every root with a vault provider exports that token as
`TF_VAR_bao_jwt`. It passes `--request-timeout=2s`, so entering the directory
without a route to `kube.gewis.nl:6443` costs two seconds and leaves the variable
unset instead of stalling on the API server's dial timeout.

`disable_mlock` is not a valid OpenBao 2.x option; it was removed and is only
warned about, not rejected.

## People log in through authentik

```sh
bao login -method=oidc
```

or **OIDC** on the UI's login screen. The method is split over two roots:
`40_openbao-config` mounts the bare `auth/oidc`, and `50_authentik-config`
(`openbao.tf`) creates the `openbao` client in [authentik](../authentik/index.md),
writes `auth/oidc/config` with its issuer and secret, and owns the roles. The mount has
no dependencies; its configuration needs the client, so it lives where the client is.

The single role, `authentik`, only accepts members of
`CBC - Application Hosting Team (ADM)`, through `bound_claims` on the `groups` claim.
That claim is built from `memberOfFlattened`, so nested membership counts — see
[the groups claim](../authentik/configuration.md#the-groups-claim-comes-from-the-directory-not-from-authentiks-groups).
authentik enforces the same group first: an expression policy bound to the `openbao`
application checks that attribute, so anyone else is refused at authentik and does
not see the app on their dashboard. A plain group binding would not do, because
authentik's own groups only hold direct members. Both checks read
`openbao_login_group` in `locals.tf`. Besides `default`, the role grants only
`ssh-sign-admin`, which signs [SSH certificates](../ssh-certificates/index.md) and
reads nothing. Management stays with OpenTofu through the Kubernetes path above.

OpenBao never returns `oidc_client_secret` when the config is read, so the
`vault_generic_endpoint` sets `ignore_absent_fields` — without it every plan would show
the secret as changed. It also sets `disable_delete`, because the config endpoint
cannot be deleted; destroying the method means removing the mount in
`40_openbao-config`.
