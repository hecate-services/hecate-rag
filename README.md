# hecate-rag

Retrieval-augmented generation as a **realm-bound mesh service**.

`hecate-rag` runs as an always-on container daemon on Hecate
infrastructure nodes (BEAM cluster, dedicated relay boxes). Agents and
services reach it via the Macula mesh — they never run their own RAG.
The service holds the index, answers queries, and optionally federates
against peer `hecate-rag` instances on other nodes via
[`macula-rag`](https://github.com/macula-io/macula-rag).

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

Substrate: [`hecate-om`](https://github.com/hecate-services/hecate-om).
See `hecate-om/guides/service_anatomy.md` for the lifecycle and
`hecate-om/guides/identity_model.md` for the town/library identity
metaphor.

## Capabilities

Advertised onto the mesh bloom-channel and discoverable by name:

| Capability | Description |
|------------|-------------|
| `hecate-rag.upload_knowledge` | Full pipeline: raw file → chunk → embed → store (server-side) |
| `hecate-rag.add_knowledge` | Add a text snippet to the index (conversational deposits from agents) |
| `hecate-rag.ingest_document` | Store a document's raw bytes as a source record (no embedding) |
| `hecate-rag.embed_document` | Chunk + embed an already-ingested doc |
| `hecate-rag.classify_topics` | Classify a document's chunks into topic labels (LLM-backed, optional) |
| `hecate-rag.prune_chunks` | Remove a document's chunks from the index (the source record stays, for a re-embed) |
| `hecate-rag.retire_document` | Remove a document for good: its chunks and its source record |
| `hecate-rag.answer_query` | Top-k retrieval against the index |
| `hecate-rag.rerank_results` | Rerank a set of hits (semantic + lexical blend) against a query |
| `hecate-rag.search_chunks_semantic` | Semantic search (text or vector query, optional topic filter) |
| `hecate-rag.get_chunk_by_id` | Chunk lookup by id |
| `hecate-rag.list_chunks_by_source` | Chunks for one source_path |
| `hecate-rag.get_source_by_id` | Source-document lookup by document_id |
| `hecate-rag.list_sources_page` | Source-document listing |
| `hecate-rag.detect_corpus_change` | Compare a hash against the last known one for a source; report whether it changed |
| `hecate-rag.schedule_reembed` | Record a durable re-embed request for a known source |

## Architecture

See [guides/architecture.md](guides/architecture.md) for the full
design, including the embedding pipeline, the gen_server
non-blocking fix, the two ingestion entry points, topic classification,
and federation wiring.

## Umbrella layout

| App | Department | Purpose |
|-----|-----------|---------|
| `rag` | shared | `rag_store`, `rag_embedder`, `rag_chunk_embedder`, `rag_embed_hecate_embedder` |
| `embed_corpus` | CMD | upload_knowledge, add_knowledge, ingest_document, embed_document, classify_topics, seed_corpus, prune_chunks, retire_document |
| `refresh_corpus` | CMD | detect_corpus_change, schedule_reembed |
| `serve_retrieval` | CMD | answer_query, rerank_results |
| `query_chunks` | QRY | get_chunk_by_id, list_chunks_by_source, search_chunks_semantic |
| `query_sources` | QRY | get_source_by_id, list_sources_page |

Vertical slicing all the way down — each desk co-locates its
command, handler, and API stub.

## Deps

- [`hecate-om`](https://github.com/hecate-services/hecate-om) — service substrate (`hecate_om_service` behaviour, identity, capabilities, health)
- [`barrel`](https://hex.pm/packages/barrel) — document + vector storage with HNSW ANN index (record mode)
- [`hecate-embedder`](https://github.com/hecate-services/hecate-embedder) — sovereign sentence-embedding capability on the mesh (NIF, `multilingual-e5-small`, 384-dim)
- [`macula-rag`](https://github.com/macula-io/macula-rag) — federated retrieval protocol
- `reckon_db` + `evoq` + `reckon_evoq` — event sourcing (transitive via hecate_om)
- `cowboy` — local HTTP for `/health` + `/api/v1/*` admin endpoints

## Build

```bash
rebar3 compile
rebar3 ct --sys_config config/test.sys.config
```

Or build the container image:

```bash
docker build -t ghcr.io/hecate-services/hecate-rag:dev .
```

## Deploy

CI pushes `ghcr.io/hecate-services/hecate-rag:latest` + `:semver` to
ghcr.io. On beam00-03, watchtower polls ghcr and recreates the
container within seconds of a new `:latest`. On msi00, podman
auto-update via Quadlet does the same on a timer.

Rollback: pin the container to a specific semver tag, back to
`:latest` after the fix ships.

See `quadlet/hecate-rag.container` for the canonical unit.

## Status

**Working, not scaffold.** All 15 mesh capabilities are real. The core
pipeline — `upload_knowledge` (raw file → chunk → embed → store) and
`add_knowledge` (text snippet → chunk → embed → store) — writes through
to a real [`barrel`](https://hex.pm/packages/barrel) record-mode
database with HNSW vector indexing. Embedding runs on
[`hecate-embedder`](https://github.com/hecate-services/hecate-embedder)
over the mesh (the beam Celerons lack AVX2), reached via `rag_embedder`
in the caller's process — never inside `rag_store`'s gen_server.

`classify_topics` classifies chunks into topic labels via NVIDIA NIM
(free tier, OpenAI-compatible API), falling back to DeepSeek when NVIDIA
cannot answer (`HECATE_TOPIC_API_KEY`, `HECATE_TOPIC_FALLBACK_API_KEY`;
either key alone is enough). `search_chunks_semantic` supports
optional topic filtering. `rerank_results` blends semantic and lexical
scores. `detect_corpus_change` compares against persisted watermarks.

Verified live end-to-end on beam03: upload → search (retrieves by
meaning, not keyword match), add_knowledge → search, topic
classification → topic-filtered search, surviving container restart
(vector index persists to mounted volume).

## License

Apache-2.0. See [LICENSE](LICENSE).
