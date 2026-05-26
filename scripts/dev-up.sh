#!/usr/bin/env bash
# One-shot dev runner: builds the image if missing, then runs it.
#
# Foreground (Ctrl+C to stop). For systemd-managed lifecycle, install
# the quadlet/hecate-rag-dev.container instead.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"

TAG="${TAG:-localhost/hecate-rag:dev}"
DATA_DIR="${DATA_DIR:-$HOME/.hecate/hecate-rag-dev}"
CORPUS_DIR="${CORPUS_DIR:-$HOME/work/codeberg.org/hecate-social/hecate-corpus}"

mkdir -p "$DATA_DIR/data" "$DATA_DIR/index"

if ! podman image exists "$TAG"; then
    echo "==> Image $TAG missing — building first"
    "$HERE/build-image.sh"
fi

echo "==> Starting hecate-rag-dev"
echo "    DATA_DIR    = $DATA_DIR"
echo "    CORPUS_DIR  = $CORPUS_DIR (mounted at /corpus)"
echo "    HTTP        = http://127.0.0.1:8470"
echo "    Ollama      = http://127.0.0.1:11434"

# Remove any previous container with the same name.
podman rm -f hecate-rag-dev >/dev/null 2>&1 || true

exec podman run --rm -it \
    --name hecate-rag-dev \
    --network host \
    -v "$DATA_DIR:/var/lib/hecate-rag" \
    -v "$CORPUS_DIR:/corpus:ro" \
    "$TAG"
