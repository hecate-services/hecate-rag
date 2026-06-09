# Plan: hecate-rag operational hardening + the knowledge mesh

**Status:** Draft / design record (2026-06-09)
**Author:** design discussion (rl + apprentice)
**Scope:** hecate-rag (this repo) + macula-rag (the federation protocol)
**Spans:** hecate-rag, macula-rag, hecate-om (identity/capabilities), reckon-db (corpus event stream)

This plan has two parts. **Part A** is near-term operational hardening of the
seed/ingest path, prompted by concrete friction (a full-corpus seed that could
not be confirmed). **Part B** is the north star this service was built for:
**rag-over-mesh** — a federation of domain-specialised hecate-rag shards that
together form a *mesh of knowledge*. Part A is also a prerequisite for Part B:
operating a fleet of edge shards needs ingest observability and efficient
embedding far more than a single central index does.

---

## Part A — Operational hardening (Phase 0)

### A1. The async seed is fire-and-forget with no observability (the core bug)

`apps/embed_corpus/src/seed_corpus/maybe_seed_corpus.erl`:

```erlang
seed_async(Params) ->
    Owner = self(),
    Pid = spawn(fun() -> Owner ! {seed_done, self(), seed(Params)} end),
    {ok, #{job_pid => Pid}}.
```

`Owner` is the Cowboy request process. It returns the `202 {accepted, job_pid}`
and moves on, so the `{seed_done, ...}` completion message — carrying the stats,
including `embed_errors` — is sent to a process that is no longer listening. The
result is discarded. The `job_pid` handed back is a raw pid string a client
cannot query over HTTP or MCP, and is likely dead by the time you would ask. So
async seeds genuinely cannot be confirmed. (Observed: a `sync=true` full-corpus
seed `fetch failed` on timeout; `sync=false` returned `accepted` but completion
was unverifiable.)

**Fix — a tracked job:**
- A job registry (ETS table or a small gen_server) keyed by a generated
  `job_id` (binary), not a raw pid.
- The worker writes progress (`files_done` / `files_total`, `chunks`, `embeds`,
  `embed_errors`, `state: running | done | failed`) and the final `stats`.
- `POST /api/rag/seed` (async) returns `{status: accepted, job_id}`.
- New `GET /api/rag/seed/status/:job_id` returns the job record.
- MCP: add a `hecate_rag_seed_status` tool wrapping the status route.
- Retain finished job records with a TTL so a poller can read the result after
  completion.

This turns async from "fire and hope" into "fire, poll, confirm."

### A2. Synchronous seed times out past a handful of files

`walk_and_index` folds over files and calls `hecate_embed:embed/2` one chunk at
a time, sequentially, inside the request. 31 files and 111 files both exceeded
the request window. Two moves, not mutually exclusive:
- **Batch the embedder.** If `hecate-embed` exposes (or can expose) an
  `embed_batch/2` over many chunks per NIF call, fold chunks into batches. This
  is a large throughput win for both sync and async, and it matters doubly on
  resource-constrained edge shards (Part B).
- **Make async-with-status the documented path** for anything beyond a few
  files; stop implying `sync=true` scales. `sync=true` stays for small,
  interactive seeds.

### A3. Minor parity

The seed command supports `exclude_globs` (see the API docstring and
`do_seed/3`), but the MCP `seed` tool schema does not expose it. Add it so MCP
callers can exclude `_build/`, `priv/`, `assets/`.

### A4. Deploy note

These take effect only after the Erlang service AND the TypeScript MCP server
(`mcp/src/index.ts`) are rebuilt and redeployed. This is a live Layer-2 service;
schedule the redeploy rather than hot-patching mid-ingest.

---

## Part B — rag-over-mesh: the knowledge mesh

### B0. What already exists (this is a scaffold, not a greenfield)

- **hecate-rag** is a complete, event-sourced RAG *node*: local multilingual
  embedder (`hecate-embed`, NIF), in-BEAM HNSW ANN (`hecate-vector`, NIF), a
  `rerank_results` slice, corpus-as-event-stream (`document_ingested_v1` →
  `project_sources` / `project_chunks` read models), capabilities advertised on
  the mesh bloom-channel via `hecate-om`.
- **macula-rag** is the realm-agnostic federation protocol (status: *Scaffold*):
  `macula_rag_advertiser` (advertises a Bloom-style summary of the shard's chunk
  topics), `macula_rag_router` (subscribes to summaries, fans a query across
  peers, merges + ranks), `macula_rag_responder` (serves incoming retrieval
  RPCs, delegates to a search callback — typically hecate-rag), `macula_rag:query/2`.
  Wire-level Macula SDK integration is stubbed `TODO`.

So the *single shard* and the *protocol shape* are built. The unbuilt and the
genuinely hard parts are routing precision, cross-shard fusion, and trust.

### B1. What rag-over-mesh brings (why it is worth finishing)

- **Specialisation beats the monolith.** Retrieval quality is domain-sensitive:
  domain-specific corpora, chunking, and embedder choice materially out-retrieve
  a general index on in-domain queries. Federation lets `hecate-rag(legal)`,
  `hecate-rag(biology)`, etc. each optimise independently. This is the strongest
  technical argument.
- **Sovereignty + provenance + trust.** Each shard is an identified Layer-1
  principal. Every result is attributable to *who curates it*. Curation becomes
  first-class: weight, filter, or exclude sources by operator and track record.
  This is the antidote to undifferentiated web-RAG slop.
- **Edge locality, offline, data residency.** A hospital hosts its protocol
  corpus on-prem; it never leaves the building but is queryable by authorised
  realm members. Data stays where it lives; only the query and the answer cross
  the mesh, under capability auth. Matches the Tier Model's offline-first ethos.
- **Permissionless growth.** Anyone stands up a domain shard and advertises it.
  The knowledge mesh grows the way the web grew, with no central gatekeeper of
  which domains may exist. New domain, new shard.
- **Agent composability.** A cross-domain agent task fans one question to legal
  + biology + finance shards and synthesises. RAG stops being a single index
  lookup and becomes routed, multi-source retrieval — a substrate for
  multi-domain reasoning.
- **A contribution / reputation economy (later).** Hosting a high-quality domain
  shard is a cooperative-contributed service; reputation accrues on retrieval
  quality. Ties into the Macula marketplace/reputation patterns.

### B2. The hard problems (where this succeeds or fails)

1. **Routing precision.** The scaffold routes by a Bloom summary of each shard's
   chunk *topics*. A Bloom membership sketch is cheap and high-recall but
   lexical and coarse: it answers "might this shard contain term T," not "is this
   shard semantically relevant." Risk: fan out too widely (latency, cost, noise)
   or miss a shard that is relevant but lexically different. **Recommendation:**
   carry a small *semantic* descriptor alongside the Bloom — a handful of corpus
   cluster centroids (or a domain-label embedding) — and let the router pick
   shards by max-centroid similarity, using the Bloom as a cheap pre-filter.
   Two-stage: descriptor-route, then in-shard HNSW retrieve.
2. **Cross-shard fusion across heterogeneous embedders.** If shards embed with
   different models, their similarity scores are NOT comparable; you cannot merge
   by score. Use rank fusion (Reciprocal Rank Fusion needs no comparable scores)
   to build a candidate set, then a *shared* cross-encoder reranker over the
   passage *text* to produce the final order. The single-shard `rerank_results`
   slice is the seed of this; the federated version reranks the merged
   cross-shard candidates. Federation unit = **text query in, ranked passages +
   provenance out**; each shard embeds locally with its own model. Heterogeneity
   then costs nothing.
3. **Trust, provenance, poisoning.** A permissionless mesh invites poisoned
   corpora and prompt-injection passages. Mitigations: principal identity
   (Layer-1 certs) on every shard; per-realm allowlists / web-of-trust over
   curators; reputation weighting by retrieval track record; **provenance
   threaded with every passage** (shard, source doc, ingest event, curator) so
   the consuming LLM is told what is trusted. Content addressing gives passage
   integrity. *Tie-in:* this is the lineage work shipped in reckon-db 5.0.0 /
   evoq 1.20.0 — a passage's provenance IS its causation/correlation lineage
   (source → ingest event → chunk), queryable via `read_by_metadata`; a federated
   query could even carry a `correlation_id` that ties all fanned shard responses
   together.
4. **Query privacy.** Fanning a query advertises your interest to every
   responder. Realm-scoping + capability auth bound *who* can see it but do not
   hide it. State the posture explicitly; private-retrieval techniques are later.
5. **Evaluation.** You cannot improve routing or fusion without a federated
   retrieval eval harness (golden query→shard→passage sets, recall@k, routing
   precision, end-to-end answer quality). Unsexy, and a hard prerequisite for
   everything above.

### B3. Phased roadmap

- **Phase 0 — Operational hardening (Part A).** Job status + batch embed.
  Prerequisite for fleet operation.
- **Phase 1 — One meshable shard, explicit-domain routing.** Finish the
  macula-rag Macula SDK wiring (advertiser publishes the shard summary; responder
  serves `query` RPCs delegating to hecate-rag's `answer_query`). Two shards,
  routing by explicit domain label. Federation unit nailed down: text in,
  ranked passages + provenance out.
- **Phase 2 — Descriptor routing + cross-shard fusion.** Add semantic centroids
  to the advertised summary; router selects shards by descriptor similarity (+
  Bloom pre-filter). RRF merge + shared cross-encoder rerank over text.
- **Phase 3 — Provenance + trust.** Provenance threaded end to end (reuse the
  reckon-db lineage primitives). Reputation weighting; per-realm allowlists.
- **Phase 4 — Freshness + economy.** Corpus merkle-root advertisement for
  staleness/integrity (`refresh_corpus` already detects change); contribution /
  reputation layer for shard hosting.

### B4. Open design decisions (for rl)

- **Router placement.** Does the router live in macula-rag on the querying
  station (current scaffold), in hecate-daemon's local client pool (Layer 3,
  per-session), or as a dedicated Layer-2 `rag-router`? Lean: keep it in
  macula-rag (realm-agnostic, reusable by non-Hecate consumers) and let the
  daemon embed it.
- **Routing signal.** Bloom-of-topics only, or Bloom + semantic centroids?
  (Recommend the latter for precision.)
- **Trust model.** Permissionless-with-reputation, realm-allowlist-only, or a
  hybrid (open discovery, realm decides what to trust)? This is the defining
  governance choice for a "mesh of knowledge."
- **Domain descriptor schema.** What exactly does a shard advertise — a free-text
  domain label, a controlled taxonomy, centroids, a corpus merkle-root, supported
  languages? This is the contract every shard and router agrees on; pin it once
  (the same lesson as the reserved metadata-key contract in reckon-proto).
- **Query-privacy posture.** Acceptable that responders see queries within a
  realm, or is blind/private retrieval a requirement before broad use?
