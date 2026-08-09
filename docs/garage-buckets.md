# garage-buckets

One OpenTofu root, `terraform/garage-buckets`, that declares Garage S3 buckets
and lands their credentials in OpenBao where exactly one Kubernetes namespace
can read them.

## The declaration

Everything is driven by one map in `main.tf`:

```hcl
buckets = {
  loki  = { size_gib = 20, namespace = "observability" }
  mimir = { size_gib = 20, namespace = "observability" }
  tempo = { size_gib = 10, namespace = "observability" }
}
```

The key is the Garage bucket name. `size_gib` becomes a Garage quota, `namespace`
is the only namespace whose pods may read the resulting credentials.

Per entry, one apply produces:

| Object | Where |
| --- | --- |
| Bucket with `max_size` quota | Garage |
| Access key `<namespace>-<bucket>`, non-expiring | Garage |
| Read+write grant on that bucket for that key, **not owner** | Garage |
| KV entry `garage/<namespace>/<bucket>` — `bucket`, `endpoint`, `region`, `access_key_id`, `secret_access_key` | OpenBao |
| Policy `garage-<namespace>-<bucket>`, `read` on that one path | OpenBao |

Plus one Kubernetes auth role per *namespace*, `garage-<namespace>`, bound to
`bound_service_account_namespaces = [<namespace>]` and carrying every policy for
that namespace's buckets. Service accounts are bound as `*`: any pod in the
namespace, nothing outside it.

`size_gib` is a cap, not a reservation. The node advertises 90G with
`replication_factor = 1`, so the quotas may sum to more than the disk — Garage
will hit ENOSPC before the quota if you overcommit.

## Which mount, and why not `secret`

This root owns its own `garage` kv-v2 mount. `terraform/openbao-config` owns
`secret`; two roots declaring the same `vault_mount` is a state fight, and a
dedicated mount makes the policy paths (`garage/data/<ns>/<bucket>`) fall out
without prefix gymnastics.

The Kubernetes auth backend itself is **not** declared here. The OpenBao Helm
release bootstraps `auth/kubernetes`, the `admin` policy and the `admin` role
through its `initialize` stanza; this root only adds roles underneath it. So
`flux/openbao` must be reconciled before the first apply.

## Credentials and reachability

Both endpoints are reachable directly, no tunnels:

| Endpoint | Default | Notes |
| --- | --- | --- |
| Garage Admin API | `http://10.82.50.100:3903` | Campus LAN only; the host has no WAN leg |
| OpenBao | `https://openbao.cbc.gewis.nl:8443` | Through the Traefik gateway |

`.envrc` exports both credentials, so there is nothing to pass by hand:

- `TF_VAR_garage_admin_token` ← `sops -d --extract '["garage-admin-token"]' secrets/s3-01.yaml`
- `TF_VAR_bao_jwt` ← `kubectl -n openbao create token openbao-admin`

That JWT is the same ServiceAccount path `terraform/openbao-config` uses; the
root logs in at `auth/kubernetes/login` as the `admin` role. The token's TTL is
an hour, and `.envrc` mints it on directory entry, so a long-idle shell needs a
`direnv reload` before an apply.

The Garage side authenticates with the master `admin_token` from
`/etc/garage.toml`, which grants every admin endpoint. Garage v2 supports scoped
tokens (`garage admin-token create --scope CreateBucket,…`) and that is the
better end state, but the token is printed exactly once at creation, so it is a
manual bootstrap rather than something this root can mint for itself.

## Applying

```sh
cd terraform/garage-buckets
tofu init
tofu plan
tofu apply
```

The access key's secret is revealed by Garage **only at creation**, so it lives
in the state file from then on. The state is PBKDF2 → AES-GCM encrypted with
`enforced = true` before it leaves the machine, same as every other root here.

Removing an entry from the map destroys the bucket. Garage refuses to delete a
non-empty bucket, so that fails the apply rather than eating data — but do not
lean on it as a safety net for a bucket you emptied yesterday.

Rotating a key means replacing the `garage_key` resource, which changes the
secret in OpenBao. Consumers break until External Secrets resyncs, which is
within its refresh interval, not instantly.

## Reading it from the cluster

External Secrets Operator runs in the `controllers` layer
(`flux/controllers/external-secrets/`). It has no deploy-time dependency on
OpenBao — it only talks to it when an `ExternalSecret` reconciles, and retries
until it answers. Each consuming namespace ships its own `ServiceAccount` +
`SecretStore` + `ExternalSecret` alongside the app in `flux/apps/<app>/`. A
`SecretStore` is namespaced, and that is the point: a `ClusterSecretStore` would
authenticate as one identity for everyone and dissolve the per-namespace
boundary this root builds.

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: garage
  namespace: observability
---
apiVersion: external-secrets.io/v1
kind: SecretStore
metadata:
  name: openbao
  namespace: observability
spec:
  provider:
    vault:
      server: http://openbao-active.openbao.svc:8200
      path: garage
      version: v2
      auth:
        kubernetes:
          mountPath: kubernetes
          role: garage-observability
          serviceAccountRef:
            name: garage
---
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: loki-s3
  namespace: observability
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: openbao
    kind: SecretStore
  target:
    name: loki-s3
  dataFrom:
    - extract:
        key: observability/loki
```

`dataFrom.extract` copies every field of the KV entry into the Secret, so the
resulting keys are `bucket`, `endpoint`, `region`, `access_key_id` and
`secret_access_key`. Use `data` with explicit `remoteRef.property` entries when
an app wants different key names.

Buckets are addressed **path-style** — `endpoint` carries no bucket, and clients
must set `force_path_style` (boto3: `addressing_style = "path"`) with region
`garage`.

The `endpoint` stored in KV is `http://s3.gewis.nl:3900`, a name the cluster
resolver answers from the `hosts` block in `flux/services/dns/corefile.yaml`. It
is deliberately not the raw address: s3-01 holds a DHCP lease, and every
consumer reading this KV entry runs inside the cluster. The Garage **Admin** API
default stays an address, because `tofu` runs on a workstation that resolves
through campus DNS, which knows nothing about that name.

## Verifying

The interesting test is the negative one; the happy path proves very little.

```sh
bao kv get garage/observability/loki

kubectl -n observability create token garage \
  | bao write auth/kubernetes/login role=garage-observability jwt=-

kubectl -n default create token default \
  | bao write auth/kubernetes/login role=garage-observability jwt=-   # must fail
```

The second login must be refused: the role binds one namespace, and a token from
anywhere else has no way in. With a valid `garage-observability` token, reading
`garage/data/<other-namespace>/…` must return 403.

End to end, from a pod holding the synced Secret:

```sh
aws --endpoint-url http://10.82.50.100:3900 s3 ls s3://loki
```

## Notes

- **The provider is young.** `vhco-pro/garage` is v0.1.x with one maintainer, and
  the OpenTofu registry holds no GPG key for it, so `tofu init` skips signature
  validation and only the checksums in `.terraform.lock.hcl` pin it. It is chosen
  because it is one of two that speak Admin API v2, which Garage 2.x requires.
  Its three resources map 1:1 onto `CreateBucket`, `CreateKey` and
  `AllowBucketKey`, so swapping providers later is mechanical.
- **One bucket per component is a simplification.** Mimir's docs recommend
  separate buckets for blocks, ruler and alertmanager rather than sharing one
  with prefixes. Loki and Tempo are fine on a single bucket each. Splitting Mimir
  later is three more map entries.
- **`replication_factor = 1`.** Every object has exactly one copy on one VM on
  one storage repository. Nothing in these buckets is backed up by being here.
