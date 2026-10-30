# Point-in-time recovery off-site

## What SeaweedFS holds

Postgres takes a base backup at 03:00 and archives WAL continuously. The
`Cluster` does not set `archive_timeout`, so CloudNativePG's default of 5 minutes
applies: a WAL segment is shipped when it fills (16 MB) or after 5 minutes,
whichever comes first. The bucket showed it — about 290 segments a day, one per
5 minutes.

Recovery replays WAL record by record and stops at `recoveryTarget.targetTime`,
so the target can be **any moment**, to the second, between the oldest base
backup in the 30-day retention and the last archived segment. The 5 minutes are
only how much can be lost, not how fine-grained a restore is.

## What Scaleway holds

The daily copy at 04:15 UTC is the same files, so the same point-in-time
recovery works from it, up to the moment of the last copy:

| Lost | Restore from | Latest target | At most lost |
| --- | --- | --- | --- |
| The cluster | SeaweedFS | the last archived segment | ~5 minutes |
| s3-01 | nothing yet — Postgres still holds its data | — | nothing, see below |
| Both | Scaleway | the last segment before the last 04:15 copy | ~24 hours |

How far back a restore can go is longer off-site. Barman's retention deletes
base backups and WAL after 30 days; in Scaleway each deletion leaves the old
version for another 30 days, which
[`RCLONE_CONFIG_SCALEWAY_VERSION_AT`](restoring.md#the-bucket-as-it-was-at-a-moment)
brings back. Together that reaches roughly 60 days into the past.

The copy runs an hour after the 03:00 base backups so it does not pick up one
half-written; a run that did would complete it the next day.

## While s3-01 is down

Postgres keeps serving, but every WAL segment it cannot archive stays in
`pg_wal` on its 50 Gi volume — about 290 segments of 16 MB, roughly 4.7 GB a
day. `LastFailedArchiveTime` fires. Bring SeaweedFS back, or restore it from
Scaleway, well before the volume fills, then take a fresh base backup so the new
archive starts from a known point.

## MariaDB

Same shape: a 03:00 base backup plus each closed binary log. Its loss window is
the time until the current binary log closes, see
[Backups](../databases/backups.md#mariadb-physical-backups-and-binlog-archiving);
the off-site copy adds the same up-to-24-hour lag.
