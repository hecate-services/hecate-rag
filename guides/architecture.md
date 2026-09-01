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
`<<"topics">` filter: over-fetches 3x top_k, post-filters by topic
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
