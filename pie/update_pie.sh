#!/usr/bin/env bash
# update_pie.sh — rebuild the pie image against the latest pi
# release, then remove the previous (now-dangling) image.
#
# Usage: ./update_pie.sh

set -euo pipefail

cd "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

[[ -f Dockerfile ]] || { echo "update_pie: no Dockerfile in $(pwd)" >&2; exit 1; }

prev_id="$(docker image inspect --format '{{.Id}}' pie:latest 2>/dev/null || true)"

echo "==> Building pie:latest with the latest @earendil-works/pi-coding-agent..."
docker build \
    --pull \
    --no-cache \
    -t pie:latest \
    --build-arg TZ="$(date +%Z)" \
    --build-arg PI_VERSION=latest \
    .

new_id="$(docker image inspect --format '{{.Id}}' pie:latest)"

if [[ -n "$prev_id" && "$prev_id" != "$new_id" ]]; then
    echo "==> Removing previous image ($prev_id)..."
    docker image rm "$prev_id" >/dev/null 2>&1 || true
fi

echo "==> Pruning any remaining dangling images..."
docker image prune -f

echo "==> Done."
docker images pie:latest
