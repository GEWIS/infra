# Longhorn interactions to handle before rollout

- **Exclude database volumes from the `default` recurring-job group.** The jobs in
  `flux/config/longhorn/recurring-jobs.yaml` snapshot and back up every default
  volume. Replica-1 database volumes would collect crash-consistent block backups
  that are redundant with the logical dumps and waste disk — put them on a storage
  class or recurring-job group that opts out.
- **The Longhorn `backupTarget` is unset.** The existing `weekly-backup` job has
  nowhere to write. Independent of the database design, but worth resolving while
  backup targets are being thought about.
