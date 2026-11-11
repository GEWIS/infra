# Copies every SeaweedFS bucket without the tag no_backup=true to
# scaleway:$DESTINATION/<bucket>, in the storage class its tag backup_class names
# (default: the remote's), through rclone crypt if it is tagged
# backup_encrypt=true. Run by seaweedfs-backup.service; see
# docs/seaweedfs-backup/. Both remotes come from RCLONE_CONFIG_* variables, crypt
# from RCLONE_CRYPT_* ones.

endpoint="$RCLONE_CONFIG_SEAWEEDFS_ENDPOINT"
# Handed to curl as a config on stdin, not --user: argv is readable by every
# local user in /proc/<pid>/cmdline. AWS keys never contain a quote.
curl_auth="user = \"$RCLONE_CONFIG_SEAWEEDFS_ACCESS_KEY_ID:$RCLONE_CONFIG_SEAWEEDFS_SECRET_ACCESS_KEY\""
tagging="$(mktemp)"
trap 'rm -f "$tagging"' EXIT

# rclone wants the crypt keys obscured; sops holds them in plain text so that
# an operator can use them too. Through stdin, so they never reach argv.
crypt_keys=""
if [ -n "${SCALEWAY_CRYPT_PASSWORD:-}" ] && [ -n "${SCALEWAY_CRYPT_SALT:-}" ]; then
  RCLONE_CRYPT_PASSWORD="$(rclone obscure - <<<"$SCALEWAY_CRYPT_PASSWORD")"
  RCLONE_CRYPT_PASSWORD2="$(rclone obscure - <<<"$SCALEWAY_CRYPT_SALT")"
  export RCLONE_CRYPT_PASSWORD RCLONE_CRYPT_PASSWORD2
  crypt_keys=1
fi

buckets="$(rclone lsf --dirs-only seaweedfs: | sed 's#/$##')"
if [ -z "$buckets" ]; then
  echo "SeaweedFS lists no buckets; refusing to run" >&2
  exit 1
fi

failed=""
for bucket in $buckets; do
  # No tags is 404 NoSuchTagSet, which means: back it up, in the default class,
  # unencrypted.
  class=""
  encrypt=""
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
      encrypt="$(sed -n 's#.*<Key>backup_encrypt</Key><Value>\([^<]*\)</Value>.*#\1#p' <<<"$tags")"
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

  # Encrypted buckets go through an on-the-fly crypt remote rooted at the
  # bucket's prefix, so the prefix stays readable and everything below it is
  # encrypted, names included. crypt objects carry no hash of the plaintext, so
  # --checksum would silently fall back to size only and miss same-size edits:
  # those compare size and modification time instead, which re-uploads with a
  # plain PUT and never copies an object already in Glacier.
  case "$encrypt" in
    "")
      target="$remote:$DESTINATION/$bucket"
      compare="--checksum"
      ;;
    true)
      if [ -z "$crypt_keys" ]; then
        echo "$bucket: tagged backup_encrypt but the crypt keys are missing; not syncing it" >&2
        failed="$failed $bucket"
        continue
      fi
      target=":crypt,remote='$remote:$DESTINATION/$bucket':"
      compare=""
      ;;
    *)
      echo "$bucket: unknown backup_encrypt '$encrypt'; not syncing it" >&2
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

  echo "syncing $bucket${class:+ as $class}${encrypt:+, encrypted}"
  # shellcheck disable=SC2086 # $compare is one flag or none
  rclone sync --fast-list $compare --stats-one-line --stats 0 -v \
    "seaweedfs:$bucket" "$target" || failed="$failed $bucket"
done

if [ -n "$failed" ]; then
  echo "failed:$failed" >&2
  exit 1
fi
