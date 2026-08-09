# Media is a `emptyDir`, and Garage cannot fix that

authentik stores uploaded application icons, flow backgrounds and avatars in a
media directory. The obvious move here is the S3 backend pointed at Garage, the
way Loki, Mimir and Tempo work. It does not survive contact with the details.

With `storage.media.backend: s3`, authentik hands the **browser** a presigned URL
straight to the S3 endpoint. Ours is `http://s3.gewis.nl:3900`: plain HTTP, on a
name only the cluster resolver answers, on a port only the campus LAN can reach.
Embedded in an HTTPS page that is mixed content, so browsers block it outright,
and off-LAN it does not resolve at all. `storage.s3.custom_domain` exists for
exactly this and would need Garage published under a real certificate first.

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
