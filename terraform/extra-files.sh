#!/usr/bin/env bash
set -euo pipefail

: "${HOST_AGE_KEY:?HOST_AGE_KEY must be set in extra_environment}"

install -d -m 0700 "$(pwd)/var/lib/sops-nix"
printf '%s' "$HOST_AGE_KEY" > "$(pwd)/var/lib/sops-nix/key.txt"
chmod 0400 "$(pwd)/var/lib/sops-nix/key.txt"
