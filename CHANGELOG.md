# Changelog

Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Versioning: [SemVer](https://semver.org/).

## [Unreleased]

### Fixed (found preparing the first real fleet deployment; v0.1.0 could not have run there)
- `config/sys.config` was a plain, hardcoded file -- no `${VAR}` templating,
  and `rebar.config`'s `relx` block never set `sys_config_src`/`vm_args_src`,
  so `RELX_REPLACE_OS_VARS` (which every compose file in `macula-io/macula-demo`
  sets) had nothing to substitute. `HECATE_DATA_DIR`, `HECATE_HEALTH_PORT`,
  `HECATE_NODE_NAME`/`HECATE_NODE_HOST`/`HECATE_COOKIE` would all have been
  silently ignored, and the release had **no `realm` key configured at all** --
  it could not have joined a specific realm. Added `config/sys.config.src` +
  `config/vm.args.src` (relx-templated, mirroring hecate-mail's proven
  pattern) and wired them into `rebar.config`. Verified live: built a real
  `prod` release, booted it with the exact env vars the fleet compose file
  sets, confirmed every value substituted correctly via a running-node RPC
  (not `eval`, which boots a throwaway instance).
- Missing `identity_key_path` in the `hecate_om` config block -- the same
  bug class hecate-mail and hecate-tube each independently hit: without it,
  `hecate_om_identity:keypair/0` returns `{error, no_keypair}` forever and
  capability advertisement silently no-ops on every republish tick, with no
  crash and no error logged. The node would have looked perfectly healthy
  (connects, `/health` green) while all 12 mesh capabilities stayed
  unreachable. Added, matching hecate-mail's own fix.
- Embedding was hardcoded to a local Ollama HTTP endpoint. The beam fleet's
  Celerons have no AVX2 (the ONNX runtime SIGILLs), which is exactly why
  `hecate-embedder` exists as a separate sovereign mesh service already used
  by e.g. Spartan's long-term memory. Added `rag_embed_hecate_embedder.erl`,
  a `barrel_embed_provider` implementation reaching `io.hecate.embed` over
  `macula:call`, and an `embed_provider` config switch (`ollama` for local
  dev, unchanged default; `hecate_embedder` for fleet deployment, set in the
  new `sys.config.src`). `embed_dim` changes accordingly: 768
  (nomic-embed-text, dev) vs. 384 (multilingual-e5-small, fleet) -- the two
  are not interchangeable databases.

## [0.1.0] - 2026-08-31

### Fixed (local dev container was 3 months stale, masking that the barrel migration below had already landed in source)
- Containerfile builder stage was missing `openssl-dev`/`zstd-dev`/
  `snappy-dev`/`lz4-dev` -- the QUIC NIF (transitively via `hecate_om`)
  and RocksDB's native build (transitively via `reckon_db`) couldn't
  compile at all. Runtime stage gained the matching `.so` packages.
- Pinned `erlang:27-alpine` -> `erlang:28-alpine`, matching every
  sibling hecate-services repo.
- `rag.app.src`/`query_chunks.app.src`/`query_sources.app.src` still
  declared `esqlite`/`hecate_vector`/`hecate_embed` as real OTP
  application dependencies -- none exist anymore post-barrel-migration
  (see the `deps` comment in `rebar.config`), and release assembly
  hard-fails on a declared-but-missing app. `barrel` added to
  `rag.app.src` where `rag_store.erl` actually needs it started.
- `config/sys.config`/`config/dev.config` had `http_port` and
  `health_port` both set to 8470 -- two separate Cowboy listeners
  self-colliding on the same port within one process.
  `config/test.sys.config` already used two distinct ports (18470/18471)
  for exactly this reason; `health_port` now matches that pattern (8471).
- Verified live end-to-end against the rebuilt `hecate-rag-dev` container:
  ingest -> embed (real Ollama call) -> `search_chunks_semantic` and
  `answer_query`, two independently-phrased queries neither containing
  the ingested word "capybara" or "rodent" both correctly retrieving the
  chunk by meaning -- real semantic retrieval, not scaffold.
- `rag_store`'s writes (`put_chunk_doc`/`put_source_doc`/`put_watermark_doc`)
  did a blind `barrel:put_doc` with no `_rev` -- barrel rejects a
  second write to an already-existing id as `{error, conflict}` rather
  than silently overwriting it. A re-`embed_document` on an
  already-embedded document (explicitly supported, see that module's
  own doc comment) was silently failing on every chunk after the
  first. New `put_doc_upsert/3` fetches the current `_rev` and retries
  once on conflict. Found live re-ingesting a real corpus.
- `open_db/0` never passed `vectordb => #{db_path => ...}` to
  `barrel:open/2` -- the vector index silently fell back to its own
  default relative path instead of the mounted persistent volume the
  document store correctly used, so semantic search came back empty
  after every container restart even though the documents themselves
  survived fine. Now points at `data_dir()/vectors`, alongside the
  docdb path. Verified live: ingested a document, searched it
  successfully, restarted the container, searched again -- same
  result, same score.

### Added
- `rerank_results`/`detect_corpus_change`/`schedule_reembed`: real
  implementations, not stubs. See their own module doc comments for
  the reasoning:
  - `detect_corpus_change` compares a caller-supplied `diff_hash`
    against a persisted watermark per `(corpus_id, source_path)` and
    only reports `changed: true` on a genuine difference (or a source
    never seen before).
  - `schedule_reembed` resolves `source_path` to the already-ingested
    document (`rag_store:find_source_by_path/1`) and records a durable
    `reembed_request` -- deliberately does NOT include a worker that
    consumes these yet; that's a separate, standing piece of
    infrastructure, not something to fabricate silently as part of
    recording the request.
  - `rerank_results`'s command shape was corrected first (the
    generated `original_ranking :: binary()` field was never usable --
    a caller has a *list* of hits, not an opaque binary; now
    `query_text` + `hits`, matching `search_chunks_semantic`'s own
    output shape). Reranks by blending each hit's existing semantic
    score with a lexical token-overlap score against the query text --
    no cross-encoder or other learned reranker exists anywhere in this
    codebase's dependency chain, and standing one up is a real
    infrastructure decision for whoever picks `reranker_model`, not
    something to invent here. `reranker_model` is accepted and passed
    through today, informational only.
  - All three routed and advertised as real mesh RPC capabilities
    (`hecate_rag_mesh_rpc.erl`, `hecate_rag_service:capabilities/0`);
    `detect_corpus_change`/`schedule_reembed` are new mesh capabilities
    (previously HTTP-only). Verified live via HTTP: change-detection's
    changed/unchanged/changed-again cycle, reembed scheduling against
    both a known and an unknown source, and reranking correctly
    promoting a lexically-relevant hit over a purely-higher-semantic
    one.
  - Two real bugs found and fixed live testing `rerank_results`
    specifically: the handler returned its internal `{Score, Hit}`
    sort-key tuples directly instead of just the hits, which jsx's
    JSON encoder cannot serialize (`badarg` in `jsx_encoder:unzip/2`
    on every call); and it read each hit's `score`/`content` fields
    with atom keys against a JSON-decoded (binary-keyed) map, so the
    lexical/semantic blend was silently scoring everything off
    defaults rather than the caller's real values.
  - Their corresponding never-fired `evoq`-sourced event modules
    (`corpus_change_detected_v1`, `reembed_scheduled_v1`,
    `results_reranked_v1`) deleted -- same reasoning `answer_query`'s
    own migration already established: a pure read/computation, or a
    write whose own durable record already IS the fact worth keeping,
    isn't a second fact worth event-sourcing.
- Initial scaffold extracted from `hecate-apps/hecate-app-rag/hecate-app-ragd`.
- Adopts the `hecate_om_service` behaviour and the four-tier
  Hecate model: services run on realm infrastructure nodes, not user
  laptops.
- Containerfile + Quadlet unit + CI publish workflow for
  `ghcr.io/hecate-services/hecate-rag`.
- Vertical slices preserved from the plugin scaffold:
  - `embed_corpus`: ingest_document, embed_document, prune_chunks
  - `refresh_corpus`: detect_corpus_change, schedule_reembed
  - `serve_retrieval`: answer_query, rerank_results
  - `project_chunks`, `project_sources`: read-model projections
  - `query_chunks`, `query_sources`: read APIs
- `test/rag_test_helpers.erl`: shared `init_per_suite`/`end_per_suite`
  helper for the three CT suites. Known, pre-existing limitation, not
  fully closed by this: `rebar3 ct` running all three suites back to
  back in one beam node can still intermittently fail with a listener
  startup race between suites (each suite starts/stops the whole
  `hecate_rag` app in turn) -- a real, reproducible test-harness gap,
  not a defect in the capabilities themselves, which are verified
  correct against the real container above.

### Not built -- named honestly rather than silently assumed
- `schedule_reembed` records requests but nothing consumes them yet --
  a standing worker that polls `priority`/`scheduled_at` and actually
  calls `embed_document` when due is separate, real infrastructure,
  not part of this slice's own job.
- The CT suite-ordering race noted above.
