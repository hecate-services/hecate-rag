# hecate-rag scripts

Helpers for the local-dev loop. All scripts assume you run them from the
repo root.

| Script | What it does |
|--------|--------------|
| `build-image.sh` | `podman build` the dev image as `localhost/hecate-rag:dev` |
| `dev-up.sh` | Foreground `podman run` with sensible defaults (host network so Ollama on 127.0.0.1 is reachable, corpus bind-mount, state under `~/.hecate/hecate-rag-dev/`) |
| `sync-checkouts.sh` | Materialise `_checkouts/` symlinks into `_checkouts_resolved/` so the container `COPY` can pick them up |
| `seed-corpus.sh` | `curl -X POST /api/rag/seed` against a running instance |
| `search.sh` | `curl -X POST /api/rag/chunks/search` against a running instance |
| `smoke-seed-and-query.escript` | Pipe into `rebar3 shell` to drive a full end-to-end seed + 4 queries + HTTP probe without a container |
| `scaffold-slices.py` | (pre-existing) generates vertical-slice stubs from a config |

## Typical first-time flow

```bash
# 1. Ensure ollama has the embedder
ollama pull nomic-embed-text

# 2. Build the dev image (only needed once, or after source changes)
scripts/sync-checkouts.sh   # if _checkouts/ has unpublished overrides
scripts/build-image.sh

# 3. Run it (foreground; Ctrl+C to stop)
scripts/dev-up.sh

# 4. In another terminal: seed the corpus
scripts/seed-corpus.sh /corpus agents-v1

# 5. Query
scripts/search.sh "what is the dossier principle"
```

## Bypass the container (fastest dev loop)

```bash
cat scripts/smoke-seed-and-query.escript \
    | rebar3 shell --config config/dev.config --apps hecate_rag
```

Boots all 41 apps in-process, seeds `philosophy/`, runs 4 queries against
both the direct slice handler and the HTTP route. Useful when iterating
on the Erlang code.

## MCP

`mcp/` ships an MCP stdio bridge that lets Claude (or any other MCP
client) call `hecate_rag_search` and `hecate_rag_seed` against
`http://127.0.0.1:8470`. See `mcp/README.md` for the wiring.
