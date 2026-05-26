#!/usr/bin/env bash
# Seed the running hecate-rag-dev instance with a markdown corpus.
#
# Usage:
#   scripts/seed-corpus.sh                   # seeds the default /corpus mount
#   scripts/seed-corpus.sh /corpus/philosophy <seed_id> <glob>
#
# Defaults assume the dev container is running with the hecate-corpus
# repo bind-mounted at /corpus (see scripts/dev-up.sh).
set -euo pipefail

ROOT_DIR="${1:-/corpus}"
SEED_ID="${2:-agents-v1}"
GLOB="${3:-**/*.md}"
URL="${URL:-http://127.0.0.1:8470/api/rag/seed}"

PAYLOAD=$(cat <<EOF
{
  "seed_id":  "$SEED_ID",
  "root_dir": "$ROOT_DIR",
  "glob":     "$GLOB",
  "exclude_globs": ["_build/", "/priv/", "/assets/", "hecate-app-template/"],
  "sync":     true
}
EOF
)

echo "==> POST $URL"
echo "$PAYLOAD" | jq . 2>/dev/null || echo "$PAYLOAD"

curl -fsS -X POST -H 'content-type: application/json' \
    -d "$PAYLOAD" "$URL" \
    | (jq . 2>/dev/null || cat)
