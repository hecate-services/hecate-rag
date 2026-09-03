# hecate-rag Architecture

## The embedding pipeline

### The problem (v0.1.2 and earlier)

`rag_store` is a single `gen_server` owning one barrel database. Barrel's
embedding policy had `fields => [<<"content">>]` with `mode => sync`, which
meant every `put_chunk/3` call triggered barrel to embed the content inline
— calling `hecate_embedder` over the mesh (30s timeout) from inside the
gen_server's `handle_call`.

If the embedder was unreachable, the gen_server blocked for 30s per chunk.
Every other call (search, get, list, size) queued behind it. The first
blocked chunk jammed the entire store.

### The fix (v0.1.5)

Barrel's embedding policy now has `fields => []` — barrel never auto-embeds.
All embedding is application-layer:

```
Caller process (agent, worker, HTTP handler)
  │
  ├── rag_embedder:embed(Text)     ← embeds via hecate_embedder (mesh) or ollama (local)
  │     │
  │     └── returns {ok, Vector}  ← 30s mesh call happens HERE, not in rag_store
  │
  └── rag_store:put_chunk_with_vector(ChunkId, Content, Meta, Vector)
        │
        └── gen_server:call        ← FAST: barrel write + HNSW insert, no outbound call
              │
              └── barrel:put_doc with _embedding pre-set
                    │
                    └── barrel indexes the vector synchronously, no embedder call
```

`rag_store:search_text/2` is also no longer a gen_server call — it embeds the
query via `rag_embedder` in the caller's process, then delegates to
`search_vector/2` (a fast gen_server call).

### Key modules

| Module | Role |
|--------|------|
| `rag_store` | gen_server: barrel reads/writes only, never blocks on embedding |
| `rag_embedder` | facade: embeds text via hecate_embedder (mesh) or ollama (local) |
| `rag_chunk_embedder` | worker: embeds a list of chunks and stores each with its vector |
| `rag_embed_hecate_embedder` | barrel_embed_provider adapter: calls `io.hecate.embed` over mesh |

## Two entry points for knowledge ingestion

### upload_knowledge — raw file pipeline

```
Caller sends: {document_id, source_path, source_type, raw_bytes}
                    │
                    ▼
  maybe_upload_knowledge:upload/1
                    │
                    ├── rag_store:upsert_source(Source)     ← store source record
                    │
                    ├── markdown_chunker:chunk_text(Bytes)  ← chunk (fast, local)
                    │
                    └── rag_chunk_embedder:embed_and_store(Chunks)
                          │
                          ├── for each chunk:
                          │     ├── rag_embedder:embed(Content)   ← in THIS process
                          │     └── rag_store:put_chunk_with_vector(Id, Content, Meta, Vector)
                          │
                          └── returns {Stored, Errors}
```

The caller sends raw bytes; the server owns chunking and embedding. This is
the bulk path for feeding corpus markdown, documentation, etc.

### add_knowledge — conversational snippet

```
Caller sends: {text, source_label?, topics?}
                    │
                    ▼
  maybe_add_knowledge:add/1
                    │
                    ├── chunk_text(Text, Label)    ← markdown_chunker or single chunk
                    │
                    ├── rag_chunk_embedder:embed_and_store(Chunks)
                    │
                    └── maybe_tag_topics(Chunks, Topics)   ← if topics provided
```

Designed for conversational deposits: an agent learns something during a
session and pushes it directly. Handles short text (< 80 bytes) that the
chunker would skip by creating a single chunk directly. Optional `topics`
field tags each chunk after storing.

### embed_document, seed_corpus and the corpus git loop

The other three writers take the same road. `embed_document` re-reads the
bytes `ingest_document` stored on the source record, chunks them and calls
`rag_chunk_embedder:embed_and_store/1`; `seed_corpus` does the same per
file of a directory; `refresh_corpus_scheduler` (the git loop) upserts the
source record for every changed file and then calls `embed_document`.

```
refresh_corpus_scheduler (every 2 min, per configured repo, per changed file)
  │
  ├── rag_store:upsert_source(#{document_id, source_path, raw_bytes})
  │
  └── maybe_embed_document:embed(#{document_id})
        │
        ├── rag_store:get_source_content(DocId)      ← the bytes just stored
        ├── markdown_chunker:chunk_text(Bytes, Path)
        └── rag_chunk_embedder:embed_and_store(Chunks)  ← content + vector, one put each
```

Until 0.1.20 these three wrote through `rag_store:put_chunk/3`, which stores
content and metadata and no vector. With `fields => []` barrel never fills
that gap, so everything the git loop ingested was fetchable verbatim and
invisible to semantic search. `put_chunk/3` is not an ingestion path; it
survives only for metadata-only test fixtures.

Two consequences of "the caller owns the vector":

- barrel keeps no text for a vector it did not embed itself, so a search
  hit's `text` is empty. `rag_store` reads the hit's content back from the
  document store under the same id before returning it.
- A store written by an older release has chunks without vectors. The
  scheduler's watermark hash is salted with an index generation
  (`?INDEX_GENERATION` in `refresh_corpus_scheduler`); bumping it makes
  every file re-ingest exactly once on the next tick. A refresh that fails
  resets the file's watermark, so the next tick retries it instead of
  waiting for the file to change.

### What the git loop does not do: deletions

The scheduler walks the files that exist. A file DELETED from a tracked
repo keeps its chunks and its source record, and goes on answering
searches as though it were current guidance -- 33 of them were, found
live on 2026-09-02, some deleted months earlier.

`hecate-rag.retire_document` is the remedy, and takes such a document
even when its source record is already gone (`prune_chunks` resolves a
document through its source record and cannot).

Automatic propagation is deliberately not built yet: "every file this
repo had is missing from disk" is also what a half-finished clone, an
empty checkout and a failed `git` look like, and the action it would
trigger is mass deletion. It needs a guard that distinguishes those
before it can be trusted to run unattended.

## Mesh replies are text-tagged at the boundary

A bare binary in a reply encodes as a CBOR byte string, which macula-cli,
macula-mcp and every non-BEAM SDK render as `0x...` hex. Every capability's
ok reply is walked once in `hecate_rag_mesh_rpc` and each binary becomes
`{text, Bin}`. The desks themselves keep returning bare binaries, because
the same desks serve HTTP through their `*_api` modules, where jsx wants
them that way. `get_document_verbatim` is the one desk that shapes itself:
its `raw_bytes` are bytes and stay bytes.

## Topic classification

Optional LLM-backed enrichment (NVIDIA NIM, OpenAI-compatible, free tier).

```
classify_topics(document_id, mode=document|per_chunk)
    │
    ├── document mode: sample 3 chunks → 1 LLM call → tag all chunks
    │
    └── per_chunk mode: classify each chunk individually → N LLM calls
```

Topics are stored as `<<"topics">>` metadata on each chunk, indexed by
barrel's `metadata_fields`. `search_chunks_semantic` accepts an optional
`<<"topics">>` filter: over-fetches 3x top_k, post-filters by topic
intersection, returns top_k filtered results.

Configuration (`topic_classifier` under `hecate_rag` app env):

```erlang
{topic_classifier, #{
    enabled  => true,
    api_key  => <<"nvapi-...">>,
    endpoint => <<"https://integrate.api.nvidia.com/v1/chat/completions">>,
    model    => <<"minimaxai/minimax-m3">>,
    timeout  => 30000
}}
```

The endpoint is OpenAI-compatible — swap `endpoint` + `model` to use any
provider. Uses `httpc` (Erlang/OTP built-in) for the API call.

## Federation

`hecate_rag_federation` wires hecate-rag into `macula-rag`'s federation
protocol at boot:

1. `macula_rag:configure(Pool, Realm)` — publishes the shard's summary
2. `macula_rag:register_responder(ShardId, Fun)` — serves incoming `query`
   RPCs, delegating to `maybe_answer_query:retrieve/1`

Federated retrieval is text-in, ranked passages + provenance out. Each
shard embeds locally with its own model — heterogeneous embedders cost
nothing because fusion uses rank fusion (RRF), not score comparison.

See [plans/PLAN_RAG_MESH.md](../plans/PLAN_RAG_MESH.md) for the full
federation roadmap (Phase 0–4).
