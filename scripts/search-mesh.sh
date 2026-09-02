#!/usr/bin/env bash
# Query the LIVE hecate-rag over the mesh (scripts/search.sh is the local
# HTTP equivalent, against a container on this box).
#
# Prints one line per hit: score, source_path, and the head of the chunk's
# own content -- content being the part that was empty on every hit before
# 0.1.20, so it is worth seeing rather than trusting.
#
# Usage:
#   scripts/search-mesh.sh "how do I set up a lab with several machines"
#   scripts/search-mesh.sh "vertical slicing" 10
#   HOST=station-fi-helsinki.macula.io:4433 scripts/search-mesh.sh "..."
set -euo pipefail

QUERY="${1:-vertical slicing}"
TOP_K="${2:-8}"
HOST="${HOST:-station-de-frankfurt.macula.io:4433}"
# The hecate realm id: a public identifier every hecate service advertises under.
REALM="${REALM:-ABB81B5A614B63551B400B810648C0C8A78EFAD845442630C94B46CC95D2FCD1}"

PAYLOAD=$(printf '{"query_text": %s, "top_k": %s}' \
    "$(printf '%s' "$QUERY" | jq -Rs .)" "$TOP_K")

macula-cli call -json -realm "$REALM" -args "$PAYLOAD" \
    "$HOST" hecate-rag.search_chunks_semantic \
  | python3 -c '
import json, sys
env = json.load(sys.stdin)
if not env.get("ok"):
    print("call failed:", json.dumps(env)[:400]); raise SystemExit(1)
hits = env["data"]["payload"]
if not hits:
    print("(no hits)"); raise SystemExit(0)
for h in hits:
    content = (h.get("content") or "").replace("\n", " ").strip()
    marker = "" if content else "   <-- EMPTY CONTENT"
    print("%.3f  %s%s" % (h.get("score", 0.0), h.get("source_path", "?"), marker))
    print("       %s" % content[:100])
'
