# hecate-rag

Retrieval-augmented generation as a **realm-bound mesh service**.

`hecate-rag` runs as an always-on container daemon on Hecate
infrastructure nodes (BEAM cluster, dedicated relay boxes). Users and
plugins on user laptops reach it via the Macula mesh — they never run
their own RAG. The service holds the index, answers queries, and
optionally federates against peer `hecate-rag` instances on other
nodes via [`macula-rag`](https://codeberg.org/macula-io/macula-rag).

## Layer position

```
Layer 4 — apps        hecate-app-rag  (Svelte UI + thin plugin shim
                                       in hecate-daemon — talks to us)
Layer 3 — session     hecate-daemon
Layer 2 — services    ▶ hecate-rag ◀  (this repo)
                                       runs on BEAM cluster + relays
Layer 1 — identity    hecate-realm
Layer 0 — kernel      macula-station
```

Substrate: [`hecate-om`](https://codeberg.org/hecate-services/hecate-om).
See `hecate-om/guides/service_anatomy.md` for the lifecycle and
`hecate-om/guides/identity_model.md` for the town/library identity
metaphor.

## Capabilities

Advertised onto the mesh bloom-channel and discoverable by name:

| Capability | Description |
|------------|-------------|
| `hecate-rag.ingest_document` | Take a document, chunk it, embed it, store |
| `hecate-rag.embed_document` | (Re-)embed an already-ingested doc |
| `hecate-rag.classify_topics` | Classify a document's chunks into topic labels (LLM-backed, optional) |
| `hecate-rag.prune_chunks` | Remove a document's chunks from the index |
| `hecate-rag.answer_query` | Top-k retrieval against the index |
| `hecate-rag.rerank_results` | Rerank a set of hits (semantic + lexical blend) against a query |
| `hecate-rag.search_chunks_semantic` | Semantic search read API |
| `hecate-rag.get_chunk_by_id` | Chunk lookup by id |
| `hecate-rag.list_chunks_by_source` | Chunks for one source_path |
| `hecate-rag.get_source_by_id` | Source-document lookup by document_id |
| `hecate-rag.list_sources_page` | Source-document listing |
| `hecate-rag.detect_corpus_change` | Compare a hash against the last known one for a source; report whether it changed |
| `hecate-rag.schedule_reembed` | Record a durable re-embed request for a known source |

## Umbrella layout

| App | Department | Purpose |
|-----|-----------|---------|
| `rag` | shared | root + notation shared across the slices |
| `embed_corpus` | CMD | ingest, embed, prune documents |
| `refresh_corpus` | CMD | detect changes, schedule re-embeds |
| `serve_retrieval` | CMD | answer queries, rerank |
| `project_chunks` | PRJ | chunk read-model projections |
| `project_sources` | PRJ | source read-model projections |
| `query_chunks` | QRY | chunk lookups + semantic search |
| `query_sources` | QRY | source metadata lookups |

Vertical slicing all the way down — each desk co-locates its
command, event, handler, and API stub. Regenerate slice stubs with
`scripts/scaffold-slices.py`.

## Deps

- [`hecate-om`](https://codeberg.org/hecate-services/hecate-om) — service substrate (`hecate_om_service` behaviour, identity, capabilities, health)
- [`hecate-vector`](https://codeberg.org/hecate-social/hecate-vector) — in-BEAM HNSW index (NIF)
- [`hecate-embed`](https://codeberg.org/hecate-social/hecate-embed) — local multilingual embedder (NIF)
- [`macula-rag`](https://codeberg.org/macula-io/macula-rag) — federated retrieval protocol
- `reckon_db` + `evoq` + `reckon_evoq` — event sourcing
- `cowboy` — local HTTP for `/health` + `/api/v1/*` admin endpoints
- `esqlite` — read-model storage

## Build

```bash
rebar3 compile
rebar3 ct
```

Or build the container image:

```bash
podman build -t ghcr.io/hecate-services/hecate-rag:dev .
```

## Deploy

Production deploy is via `hecate-gitops`:

1. CI pushes `ghcr.io/hecate-services/hecate-rag:latest` + `:semver`
2. Operator commits Quadlet + env to `hecate-gitops/by-node/<node>/`
3. Reconciler symlinks into `/etc/containers/systemd/`
4. systemd boots the container; podman auto-update keeps it fresh

See `quadlet/hecate-rag.container` for the canonical unit + the
`hecate-om/guides/container_deployment.md` for the broader story.

## Status

**Working, not scaffold.** All 12 mesh capabilities are real: `ingest_document`,
`embed_document`, `prune_chunks`, `get_chunk_by_id`, `list_chunks_by_source`,
`search_chunks_semantic`, `get_source_by_id`, `list_sources_page`,
`answer_query`, `rerank_results`, `detect_corpus_change`, and
`schedule_reembed`. The first nine write through to a real
[`barrel`](https://hex.pm/packages/barrel) record-mode database (document +
vector, kept in sync automatically) and a real Ollama embedder -- verified
live end-to-end (ingest -> embed -> semantic search -> answer_query, two
independently-phrased queries both correctly retrieving the same ingested
chunk by meaning, not keyword match), including surviving a real container
restart (the vector index now persists to the mounted volume, not its own
default path).

`rerank_results` blends each hit's semantic score with a lexical
token-overlap score against the query text -- no cross-encoder or other
learned reranker exists in this codebase's dependency chain, and standing
one up is a real infra decision for whoever picks `reranker_model`, not
invented here. `detect_corpus_change` compares a caller-supplied hash
against a persisted watermark and only reports a real change.
`schedule_reembed` records a durable request; nothing consumes it yet -- a
polling worker is separate, standing infrastructure, not part of this
slice.

Extracted from the prior `hecate-apps/hecate-app-rag/hecate-app-ragd` plugin
scaffold (2026-05-18); the plugin contract has been swapped for the
`hecate_om_service` behaviour.

## License

Apache-2.0. See [LICENSE](LICENSE).
