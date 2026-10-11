# Media is an `emptyDir`

authentik stores uploaded application icons, flow backgrounds and avatars in a
media directory. The obvious move is the S3 backend pointed at SeaweedFS, the
way Loki, Mimir and Tempo work. It was ruled out when this was set up.

With `storage.media.backend: s3`, authentik hands the **browser** a presigned URL
straight to the S3 endpoint. That endpoint used to be plain HTTP on a LAN-only
name, which browsers block as mixed content and off-LAN clients cannot resolve.
It is now [`https://s3.gewis.nl`](../cluster/s3.md), so that objection is gone,
but whether authentik's URLs actually work through it is untested.

With the file backend, authentik serves media from its own listener —
`internal/web/static.go` reads `storage.media.file.path` and serves it — which
means it arrives over the same HTTPS route as everything else and simply works.

So the file backend it is, at `/media`, on an `emptyDir` mounted into both
Deployments. What that costs:

- Uploaded media does not survive a pod restart.
- Server and worker have separate copies, so an upload through the server is not
  visible to the worker.

Both are cosmetic. Everything authentik needs to function ships in the image, and
application icons can be given as URLs instead of uploads. The `emptyDir` is
there so the writes land somewhere explicit rather than in the container layer.

The real fix, when it matters, is a ReadWriteMany volume shared by both
Deployments — Longhorn can do it through its share-manager. It is not worth a
volume on a cluster with roughly 1 GiB of schedulable headroom per node, for
files that are decoration.
