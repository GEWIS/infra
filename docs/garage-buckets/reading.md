# Reading it from the cluster

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
