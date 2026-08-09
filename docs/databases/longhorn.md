# Longhorn interactions

- **Database volumes are excluded from the `default` recurring-job group**, via
  the `recurringJobSelector` on `longhorn-single`. How that works, and why
  removing the label instead does not, is in [Postgres](postgres.md).
- **The Longhorn `backupTarget` is unset.** The existing `weekly-backup` job has
  nowhere to write. Independent of the database design, but worth resolving while
  backup targets are being thought about.
