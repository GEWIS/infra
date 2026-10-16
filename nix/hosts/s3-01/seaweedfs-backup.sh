# Copies every SeaweedFS bucket without the tag no_backup=true to
# scaleway:$DESTINATION/<bucket>. Run by seaweedfs-backup.service; see
# docs/seaweedfs-backup/. Both remotes come from RCLONE_CONFIG_* variables.

endpoint="$RCLONE_CONFIG_SEAWEEDFS_ENDPOINT"
credentials="$RCLONE_CONFIG_SEAWEEDFS_ACCESS_KEY_ID:$RCLONE_CONFIG_SEAWEEDFS_SECRET_ACCESS_KEY"
tagging="$(mktemp)"
trap 'rm -f "$tagging"' EXIT

buckets="$(rclone lsf --dirs-only seaweedfs: | sed 's#/$##')"
if [ -z "$buckets" ]; then
  echo "SeaweedFS lists no buckets; refusing to run" >&2
  exit 1
fi

failed=""
for bucket in $buckets; do
  # No tags is 404 NoSuchTagSet, which means: back it up.
  status="$(curl --silent --show-error --output "$tagging" --write-out '%{http_code}' \
    --aws-sigv4 "aws:amz:$RCLONE_CONFIG_SEAWEEDFS_REGION:s3" --user "$credentials" \
    "$endpoint/$bucket?tagging")" || status=000
  case "$status" in
    200)
      if tr -d '[:space:]' <"$tagging" | grep -q '<Key>no_backup</Key><Value>true</Value>'; then
        echo "skipping $bucket: tagged no_backup"
        continue
      fi
      ;;
    404) ;;
    *)
      echo "$bucket: reading its tags failed with HTTP $status; not syncing it" >&2
      failed="$failed $bucket"
      continue
      ;;
  esac

  # An empty source would turn every object in the copy into a delete marker,
  # e.g. after s3-01 is rebuilt; refuse instead.
  if [ -z "$(rclone lsf -R --files-only "seaweedfs:$bucket" | head -n 1)" ]; then
    echo "seaweedfs:$bucket is empty or unreadable; not syncing it" >&2
    failed="$failed $bucket"
    continue
  fi

  echo "syncing $bucket"
  rclone sync --fast-list --checksum --stats-one-line --stats 0 -v \
    "seaweedfs:$bucket" "scaleway:$DESTINATION/$bucket" || failed="$failed $bucket"
done

if [ -n "$failed" ]; then
  echo "failed:$failed" >&2
  exit 1
fi
