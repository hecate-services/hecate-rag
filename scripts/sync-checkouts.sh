#!/usr/bin/env bash
# Materialise _checkouts/ symlinks into a plain directory tree
# (_checkouts_resolved/) so the container build can COPY them without
# following symlinks.
#
# Run this whenever you update a sibling repo (hecate-embed,
# hecate-vector, …) and want the dev container to pick it up.
#
# Skips _build/, .git/, and native/*/target/ to keep the image small.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"

CHECKOUTS="$ROOT/_checkouts"
RESOLVED="$ROOT/_checkouts_resolved"

if [[ ! -d $CHECKOUTS ]]; then
    echo "==> $CHECKOUTS missing; nothing to sync."
    exit 0
fi

rm -rf "$RESOLVED"
mkdir -p "$RESOLVED"

while IFS= read -r -d '' link; do
    dep="$(basename "$link")"
    src="$(readlink -f "$link")"
    echo "==> $dep <- $src"
    rsync -a \
        --exclude='_build' \
        --exclude='.git' \
        --exclude='native/*/target' \
        --exclude='priv/lib' \
        "$src/" "$RESOLVED/$dep/"
done < <(find "$CHECKOUTS" -mindepth 1 -maxdepth 1 -type l -print0)

echo "==> Resolved checkouts in $RESOLVED:"
ls -la "$RESOLVED"
