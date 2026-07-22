#!/usr/bin/env bash
# update_kloot.sh — rebuild the kloot image against the latest Claude Code
# release, then remove the previous (now-dangling) image.
#
# Usage: ./update_kloot.sh

set -euo pipefail

cd "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

[[ -f Dockerfile ]] || { echo "update_kloot: no Dockerfile in $(pwd)" >&2; exit 1; }

prev_id="$(docker image inspect --format '{{.Id}}' kloot:latest 2>/dev/null || true)"

echo "==> Building kloot:latest with the latest @anthropic-ai/claude-code..."
docker build \
    --pull \
    --no-cache \
    -t kloot:latest \
    --build-arg TZ="$(date +%Z)" \
    --build-arg CLAUDE_CODE_VERSION=latest \
    .

new_id="$(docker image inspect --format '{{.Id}}' kloot:latest)"

if [[ -n "$prev_id" && "$prev_id" != "$new_id" ]]; then
    echo "==> Removing previous image ($prev_id)..."
    docker image rm "$prev_id" >/dev/null 2>&1 || true
fi

echo "==> Pruning any remaining dangling images..."
docker image prune -f

echo "==> Done."
docker images kloot:latest
