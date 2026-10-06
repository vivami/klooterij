#!/usr/bin/env bash
# update_mister-all.sh — rebuild the mister-all image against the latest Mistral Vibe
# release, then remove the previous (now-dangling) image.
#
# Usage: ./update_mister-all.sh

set -euo pipefail

cd "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

[[ -f Dockerfile ]] || { echo "update_mister-all: no Dockerfile in $(pwd)" >&2; exit 1; }

prev_id="$(docker image inspect --format '{{.Id}}' mister-all:latest 2>/dev/null || true)"

echo "==> Building mister-all:latest with the latest mistral-vibe..."
docker build \
    --pull \
    --no-cache \
    -t mister-all:latest \
    --build-arg TZ="$(date +%Z)" \
    --build-arg VIBE_VERSION=latest \
    .

new_id="$(docker image inspect --format '{{.Id}}' mister-all:latest)"

if [[ -n "$prev_id" && "$prev_id" != "$new_id" ]]; then
    echo "==> Removing previous image ($prev_id)..."
    docker image rm "$prev_id" >/dev/null 2>&1 || true
fi

echo "==> Pruning any remaining dangling images..."
docker image prune -f

echo "==> Done."
docker images mister-all:latest
