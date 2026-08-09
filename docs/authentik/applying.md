# Applying

Order matters once, on the first install, because the database credential is
minted outside the cluster.

```sh
cd terraform/postgres-databases
tofu init
tofu apply
```

That writes `postgres/authentik/authentik` into OpenBao. Only then push the
manifests: both External Secrets — the one CloudNativePG reads to create the
role, and the one authentik reads to connect — resolve against that path, and
until it exists they produce nothing, `DatabaseRole` has no password, and the
pods sit in `CreateContainerConfigError` because their `envFrom` Secret is
absent. It recovers on its own the moment the path appears; it just looks like a
failed deploy in the meantime.

Once Flux has reconciled:

```sh
kubectl -n postgres get cluster postgres
kubectl -n authentik get externalsecret,pods
curl -sSf https://authentik.cbc.gewis.nl:8443/-/health/ready/
```

`/-/health/ready/` returns 200 only after the migrations finish, so it is the
honest readiness signal. Log in at `/if/flow/default-authentication-flow/` as
`akadmin` with the password from the sealed secret.

## The port is part of the issuer

The gateway is published on **8443**, not 443. Everything OIDC therefore carries
the port — the issuer is
`https://authentik.cbc.gewis.nl:8443/application/o/<slug>/`, and every redirect
URI registered in authentik and in the relying party has to match it exactly. A
mismatch surfaces as an opaque login failure rather than anything that names the
port, so it is worth getting right the first time.
