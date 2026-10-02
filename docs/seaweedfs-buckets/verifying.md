# Verifying

The interesting tests are the negative ones; the happy path proves very little.

Commands below use `http://s3.gewis.nl:8333`, which resolves inside the cluster
— run them from a pod, or substitute the address `http://10.82.50.100:8333` on a
workstation, where campus DNS does not know the name.

## The apply converged

```sh
cd terraform/40_seaweedfs-buckets
tofu plan            # must report: No changes.
tofu output buckets
```

A second `plan` reporting no drift is the real check: it proves the provider
reads back what it wrote over SeaweedFS's IAM API rather than only writing.

## Buckets and identities exist

With the admin keys from `.envrc` in `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY`:

```sh
aws --endpoint-url http://s3.gewis.nl:8333 s3api list-buckets
aws --endpoint-url http://s3.gewis.nl:8333 iam list-users
aws --endpoint-url http://s3.gewis.nl:8333 iam list-access-keys --user-name observability-loki
```

## A minted key is confined to its bucket

Export one bucket's credentials out of OpenBao, then try both buckets:

```sh
export AWS_ACCESS_KEY_ID=$(bao kv get -field=access_key_id seaweedfs/observability/loki)
export AWS_SECRET_ACCESS_KEY=$(bao kv get -field=secret_access_key seaweedfs/observability/loki)

echo probe | aws --endpoint-url http://s3.gewis.nl:8333 s3 cp - s3://loki/probe
aws --endpoint-url http://s3.gewis.nl:8333 s3 rm s3://loki/probe

echo probe | aws --endpoint-url http://s3.gewis.nl:8333 s3 cp - s3://mimir/probe   # must fail
```

The last one must come back `AccessDenied`: the user policy
`loki-read-write` grants `s3:*` on `arn:aws:s3:::loki` and `arn:aws:s3:::loki/*`
only.

## The OpenBao boundary

```sh
bao kv get seaweedfs/observability/loki

kubectl -n observability create token seaweedfs \
  | bao write auth/kubernetes/login role=seaweedfs-observability jwt=-

kubectl -n default create token default \
  | bao write auth/kubernetes/login role=seaweedfs-observability jwt=-   # must fail
```

The second login must be refused: the role binds one namespace, and a token from
anywhere else has no way in. With a valid `seaweedfs-observability` token,
reading `seaweedfs/data/<other-namespace>/…` must return 403.

## If IAM writes fail

`AccessDenied: IAM write operations are disabled on this server` on any apply
means s3-01 is running without `-s3.iam.readOnly=false`, which is the upstream
default. That is a host-side setting, not a credential problem —
[SeaweedFS on s3-01](../s3-01/seaweedfs.md).
