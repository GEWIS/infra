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
  name: seaweedfs
  namespace: observability
---
apiVersion: external-secrets.io/v1
kind: SecretStore
metadata:
  name: seaweedfs
  namespace: observability
spec:
  provider:
    vault:
      server: http://openbao-active.openbao.svc:8200
      path: seaweedfs
      version: v2
      auth:
        kubernetes:
          mountPath: kubernetes
          role: seaweedfs-observability
          serviceAccountRef:
            name: seaweedfs
---
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: loki-s3
  namespace: observability
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: seaweedfs
    kind: SecretStore
  target:
    name: loki-s3
  data:
    - secretKey: S3_ACCESS_KEY_ID
      remoteRef:
        key: observability/loki
        property: access_key_id
    - secretKey: S3_SECRET_ACCESS_KEY
      remoteRef:
        key: observability/loki
        property: secret_access_key
```

The `vault` provider `path` is the kv-v2 mount this root owns, and the `role` is
the per-namespace Kubernetes auth role from [Which mount](mount.md). The KV keys
(`observability/loki`, `observability/mimir`, `observability/tempo`) and their
properties (`access_key_id`, `secret_access_key`) did not change at the cutover;
only the store, the ServiceAccount and the role were renamed.

Only the two key fields are pulled. `bucket`, `endpoint` and `region` also sit in
the KV entry, but they are not secrets and the charts carry them in values;
`dataFrom.extract` would copy all five into the Secret if an app wanted that.

Buckets are addressed **path-style** — `endpoint` carries no bucket, and clients
must set `force_path_style` (boto3: `addressing_style = "path"`) with region
`us-east-1`.

The `endpoint` stored in KV is `http://s3.gewis.nl:8333`, a name the cluster
resolver answers from the `hosts` block in `flux/services/dns/corefile.yaml`. It
is deliberately not the raw address: s3-01 holds a DHCP lease, and every
consumer reading this KV entry runs inside the cluster. The
`seaweedfs_endpoint` default used by `tofu` stays an address, because it runs on
a workstation that resolves through campus DNS, which knows nothing about that
name.
