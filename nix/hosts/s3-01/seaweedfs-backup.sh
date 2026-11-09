# Copies every SeaweedFS bucket without the tag no_backup=true to
# scaleway:$DESTINATION/<bucket>, in the storage class its tag backup_class names
# (default: the remote's). Run by seaweedfs-backup.service; see
# docs/seaweedfs-backup/. Both remotes come from RCLONE_CONFIG_* variables.

endpoint="$RCLONE_CONFIG_SEAWEEDFS_ENDPOINT"
# Handed to curl as a config on stdin, not --user: argv is readable by every
# local user in /proc/<pid>/cmdline. AWS keys never contain a quote.
curl_auth="user = \"$RCLONE_CONFIG_SEAWEEDFS_ACCESS_KEY_ID:$RCLONE_CONFIG_SEAWEEDFS_SECRET_ACCESS_KEY\""
tagging="$(mktemp)"
trap 'rm -f "$tagging"' EXIT

buckets="$(rclone lsf --dirs-only seaweedfs: | sed 's#/$##')"
if [ -z "$buckets" ]; then
  echo "SeaweedFS lists no buckets; refusing to run" >&2
  exit 1
fi

failed=""
for bucket in $buckets; do
  # No tags is 404 NoSuchTagSet, which means: back it up, in the default class.
  class=""
  status="$(curl --silent --show-error --output "$tagging" --write-out '%{http_code}' \
    --aws-sigv4 "aws:amz:$RCLONE_CONFIG_SEAWEEDFS_REGION:s3" --config - \
    "$endpoint/$bucket?tagging" <<<"$curl_auth")" || status=000
  case "$status" in
    200)
      tags="$(tr -d '[:space:]' <"$tagging")"
      if [[ "$tags" == *'<Key>no_backup</Key><Value>true</Value>'* ]]; then
        echo "skipping $bucket: tagged no_backup"
        continue
      fi
      class="$(sed -n 's#.*<Key>backup_class</Key><Value>\([^<]*\)</Value>.*#\1#p' <<<"$tags")"
      ;;
    404) ;;
    *)
      echo "$bucket: reading its tags failed with HTTP $status; not syncing it" >&2
      failed="$failed $bucket"
      continue
      ;;
  esac

  # A typo would otherwise only surface on the next upload, as a rejected PUT.
  # The class goes into a connection string, which overrides it on this remote
  # for this one sync and leaves the seaweedfs remote alone.
  case "$class" in
    "") remote="scaleway" ;;
    STANDARD | GLACIER) remote="scaleway,storage_class=$class" ;;
    *)
      echo "$bucket: unknown backup_class '$class'; not syncing it" >&2
      failed="$failed $bucket"
      continue
      ;;
  esac

  # An empty source would turn every object in the copy into a delete marker,
  # e.g. after s3-01 is rebuilt; skip it instead. A listing that fails is not
  # an empty bucket, so that still fails the run.
  if ! size="$(rclone size --fast-list --json "seaweedfs:$bucket")"; then
    echo "$bucket: listing its objects failed; not syncing it" >&2
    failed="$failed $bucket"
    continue
  fi
  if [[ "$size" == *'"count":0,'* ]]; then
    echo "skipping $bucket: no objects"
    continue
  fi

  echo "syncing $bucket${class:+ as $class}"
  rclone sync --fast-list --checksum --stats-one-line --stats 0 -v \
    "seaweedfs:$bucket" "$remote:$DESTINATION/$bucket" || failed="$failed $bucket"
done

if [ -n "$failed" ]; then
  echo "failed:$failed" >&2
  exit 1
fi
