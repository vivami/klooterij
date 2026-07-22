#!/usr/bin/env bash
# update_koodex.sh — rebuild the koodex image against the latest Codex CLI
# release, then remove the previous (now-dangling) image.
#
# Usage: ./update_koodex.sh

set -euo pipefail

cd "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

[[ -f Dockerfile ]] || { echo "update_koodex: no Dockerfile in $(pwd)" >&2; exit 1; }

prev_id="$(docker image inspect --format '{{.Id}}' koodex:latest 2>/dev/null || true)"

echo "==> Building koodex:latest with the latest @openai/codex..."
docker build \
    --pull \
    --no-cache \
    -t koodex:latest \
    --build-arg TZ="$(date +%Z)" \
    --build-arg CODEX_VERSION=latest \
    .

new_id="$(docker image inspect --format '{{.Id}}' koodex:latest)"

if [[ -n "$prev_id" && "$prev_id" != "$new_id" ]]; then
    echo "==> Removing previous image ($prev_id)..."
    docker image rm "$prev_id" >/dev/null 2>&1 || true
fi

echo "==> Pruning any remaining dangling images..."
docker image prune -f

echo "==> Done."
docker images koodex:latest
