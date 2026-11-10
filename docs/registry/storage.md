# Storage

Blobs and manifests live in the SeaweedFS bucket `zot`, reached at
`https://s3.gewis.nl` path-style, region `us-east-1`. The key pair comes from
OpenBao `seaweedfs/zot/zot` through the `zot-s3` ExternalSecret as
`AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY`; `config.json` carries no secret.

Everything else is BoltDB in `rootDirectory`, `/var/lib/registry`, on the
Longhorn PVC `zot-pvc-zot-0` (2Gi, default class), with `remoteCache: false`:

| File | Holds |
| --- | --- |
| `meta.db` | repository metadata for search and the UI, users' API keys and preferences |
| `cache.db` | the dedupe index: which stored blob a digest points at |

**The PVC is not a cache.** With `dedupe` on, a blob pushed twice is stored once
and the second copy is a placeholder resolved through `cache.db`, so losing the
volume loses more than API keys. It is on the default class, so the weekly
[Longhorn backup](../databases/longhorn.md) covers it.

zot runs as a single-replica StatefulSet (`persistence: true`): an upgrade stops
the old pod before the new one claims the volume.
