# Applying

Order matters once, on the first install, because the database and its
credential are both made outside the cluster.

```sh
cd terraform/40_databases
tofu init
tofu apply
```

That creates the `authentik` role and database, and writes
`postgres/authentik/authentik` into OpenBao. Only then push the manifests: the
`ExternalSecret` in the `authentik` namespace resolves against that path, and
until it exists the pods sit in `CreateContainerConfigError` because their
`envFrom` Secret is absent. It recovers on its own the moment the path appears;
it just looks like a failed deploy in the meantime.

That apply is a single command; the provisioner credential it logs in with is a
credential CloudNativePG generated at bootstrap — see [Postgres](../databases/postgres.md).
The root also reads the MariaDB provisioner Secret, so the MariaDB cluster must
exist too.

Once Flux has reconciled:

```sh
kubectl -n postgres get clusters.postgresql.cnpg.io postgres
kubectl -n authentik get externalsecret,pods
curl -sSf https://authentik.gewis.nl/-/health/ready/
```

`/-/health/ready/` returns 200 only after the migrations finish, so it is the
honest readiness signal. Log in at `/if/flow/default-authentication-flow/` as
`akadmin` with the password from the sealed secret.

## The host is part of the issuer

The issuer is `https://authentik.gewis.nl/application/o/<slug>/`, and every
redirect URI registered in authentik and in the relying party has to match it
exactly, scheme, host, port and path. A mismatch surfaces as an opaque login
failure rather than anything that names the URL, so it is worth getting right
the first time.
