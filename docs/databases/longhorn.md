# Longhorn interactions

- **Database volumes are excluded from the `default` recurring-job group**, via
  the `recurringJobSelector` on `longhorn-single`. How that works, and why
  removing the label instead does not, is in [Postgres](postgres.md).

## Backups go to Scaleway `bu-k3s`

The default backup target is `s3://bu-k3s@nl-ams/`, set under
`defaultBackupStore` in `flux/20_controllers/longhorn/helm-release.yaml`. The
`weekly-backup` recurring job writes there for every volume in the `default`
group and keeps 26 backups per volume.

The credentials are the SealedSecret `backup-credentials` in
`flux/20_controllers/longhorn/backup-sealed-secret.yaml`, with `AWS_ACCESS_KEY_ID`,
`AWS_SECRET_ACCESS_KEY`, `AWS_REGION` (`nl-ams`) and `AWS_ENDPOINTS`
(`https://s3.nl-ams.scw.cloud`). Seal it the same way as the
[Grafana secret](../observability/secret.md), into `longhorn-system`.

The bucket is the one the previous cluster backed up to. Its backups show up in
this cluster's UI and restore from there. Deleting a backup in the UI deletes it
from the bucket, whichever cluster made it.

## The UI is at `longhorn.gewis.nl`

`flux/50_apps/longhorn/ingressroute.yaml` publishes `longhorn-frontend` behind the
authentik proxy outpost, like [Hubble](../observability/hubble.md). The UI can
delete volumes and backups, so unlike Hubble it only admits the groups in
`proxy_access_groups` — see
[authentik configuration](../authentik/configuration.md#oidc-clients-are-a-map).
