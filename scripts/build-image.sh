#!/usr/bin/env bash
# Build the local-dev container image.
#
# Tag: localhost/hecate-rag:dev (used by `dev-up.sh` and the dev Quadlet)
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"

TAG="${TAG:-localhost/hecate-rag:dev}"

echo "==> Building $TAG from $ROOT"
podman build \
    -t "$TAG" \
    -f "$ROOT/Containerfile" \
    "$ROOT"

echo "==> Built: $TAG"
podman image inspect "$TAG" --format '    size: {{ .Size }} bytes'
