#!/usr/bin/env bash
# Query the running hecate-rag instance.
#
# Usage:
#   scripts/search.sh "what is the dossier principle"
#   scripts/search.sh "vertical slicing" 5
set -euo pipefail

QUERY="${1:-vertical slicing}"
TOP_K="${2:-5}"
URL="${URL:-http://127.0.0.1:8470/api/rag/chunks/search}"

PAYLOAD=$(printf '{"query_text": %s, "top_k": %s}' \
    "$(printf '%s' "$QUERY" | jq -Rs .)" \
    "$TOP_K")

curl -fsS -X POST -H 'content-type: application/json' \
    -d "$PAYLOAD" "$URL" \
    | (jq . 2>/dev/null || cat)
