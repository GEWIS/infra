# Hostnames are set with a HostnameConfig document

Talos 1.13 seeds every machine with a `HostnameConfig` document set to
`auto: stable`, which produces names like `talos-d1w-560`. The v1alpha1
`machine.network.hostname` field is **refused** while that document exists
(`static hostname is already set in v1alpha1 config`), so the fix is to patch the
document rather than the legacy field:

```yaml
apiVersion: v1alpha1
kind: HostnameConfig
hostname: talos-01
auto: off
```

`auto: off` is required: `auto` and `hostname` are mutually exclusive, and the
default `stable` collides with a static name. The Kubernetes node name follows
the hostname and is immutable — renaming a live node registers a brand-new
`Node` and orphans the old one, so the names are pinned before bootstrap.
