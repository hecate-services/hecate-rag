# Changelog

Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Versioning: [SemVer](https://semver.org/).

## [0.1.11] - 2026-09-01

### Changed (diagnostic, not a fix)

- Reordered `hecate_rag_service:capabilities()` -- `get_document_verbatim`
  moved from 14th of 16 to 1st. Live experiment: 0.1.10's hecate_om
  bump did NOT resolve `get_document_verbatim` staying `unknown_method`
  even on a fresh boot with a stable node identity, ruling out the
  tombstone-race theory (same-source re-registration always passes
  `macula_remote_advertise_registry`'s carve-out, regardless of
  timing). Calling both through the default station and directly
  through hecate-rag's own configured seed station
  (`station-it-milan.macula.io`) fails identically, ruling out
  inter-station gossip lag too. Remaining hypothesis: a boot-time
  ADVERTISE burst (32 wire frames -- 16 capabilities x bare +
  org-qualified -- sent back-to-back via `advertise_one/7`'s
  `lists:foldl`) hits a station-side or SDK-side rate limit around
  this capability's position, silently, since `hecate_om_capabilities`
  only knows the frame was sent, not that the station indexed it. If
  breakage follows the position (`ingest_document`, now 14th, breaks
  instead) that confirms it. Revert this reorder once the result is
  known.

## [0.1.10] - 2026-09-01

### Fixed

- Bumped `hecate_om` `0.18.0` -> `0.19.0`. Fixes a live bug found on
  beam03: `get_document_verbatim`'s `procedure_advertisement` stayed
  advertised but uncallable (`unknown_method`) for 45+ minutes while
  sibling capabilities from the same advertise batch self-healed,
  traced to hecate_om's periodic re-advertise timer racing
  macula-station's tombstone TTL at an identical fixed 30s period. See
  `hecate_om`'s own CHANGELOG `[0.19.0]` entry for the root cause; no
  code change needed on this side beyond the dependency bump.

## [0.1.9] - 2026-09-01

### Fixed

- `hecate_rag_corpus_sync_nif` failed every clone/fetch against a real
  `https://...` URL with `"there is no TLS stream available"` — found
  live on beam03 immediately after 0.1.8's own two crash-loop fixes
  landed and stopped masking it. Cause: the crate's `git2` dependency
  declares `default-features = false` (needed to avoid pulling in
  `ssh`, deliberately unsupported here) but that also silently drops
  the `https` feature and its TLS backend — `vendored-libgit2` only
  controls whether libgit2's C sources are vendored, not which
  transports get compiled in. No local test caught this because every
  existing Rust test clones/fetches over a plain file path (a local
  bare repo), never HTTPS. Fixed by adding `https` and
  `vendored-openssl` (keeping the "no OS dependency" property intact
  on Alpine/musl) to the feature list, plus a new test that clones a
  real public repo over HTTPS — confirmed it reproduces the exact
  production error without the fix and passes with it.

## [0.1.8] - 2026-09-01

### Added

- `hecate-rag.get_document_verbatim`: exact, byte-for-byte fetch of a
  corpus document by path, composing the already-existing
  `rag_store:find_source_by_path/1` + `rag_store:get_source_content/1`
  (used internally by `schedule_reembed`/`embed_document` but never
  mesh-exposed) into one new QRY desk
  (`apps/query_sources/src/get_document_verbatim/`). `get_source_by_id`
  (the existing mesh-exposed lookup) returns only metadata, never
  `raw_bytes` — this is the first way to get exact content over the
  mesh rather than a RAG-reranked approximation of it. Path is
  `"<repo-id>/<relative-path>"` (e.g. `"hecate-corpus/roles/devops.md"`)
  — see the `corpus_git_sync`/`corpus_repos_config` entry below for why.
- `maybe_seed_corpus.erl` now calls `rag_store:upsert_source/1` per
  file (previously only `put_chunk`), bringing the bulk directory-seed
  path to parity with the per-document `ingest_document`/`upload_knowledge`
  paths — bulk-seeded files are exact-fetchable via
  `get_document_verbatim`, not chunks-only.
- `refresh_corpus_scheduler` (new gen_server, `src/`): ticks every 2
  minutes, reads `corpus_repos_config` for the configured repo list,
  and for every file under each repo's path whose hash
  `detect_corpus_change` reports changed, records the request via
  `schedule_reembed` and immediately refreshes it (`upsert_source` with
  current bytes, then `maybe_embed_document:embed`) — closes the loop
  those two capabilities left open since their own introduction
  (`schedule_reembed` recorded requests but nothing consumed them).
  `document_id`/`source_path` are namespaced `<repo-id>/<relative-path>`
  so two configured repos sharing a same-named file don't collide in
  `rag_store`, which has no repo-scoping of its own.
- `corpus_repos_config` (new module, `src/`): reads a JSON file (app
  env `hecate_rag.corpus_repos_config`, default
  `/etc/hecate-rag/corpus-repos.json`) naming which git repos to track
  — `{"repos": [{"id", "url", "branch"}, ...]}` — and derives each
  one's local clone path (`<data_dir>/corpus/<id>/`, never a config
  field, so it can't be misconfigured onto a colliding path). Re-read
  from disk on every poll tick by both `corpus_git_sync` and
  `refresh_corpus_scheduler`, not cached, so editing the file takes
  effect on their very next tick with no restart.
- `corpus_git_sync` (new gen_server) + `hecate_rag_corpus_sync_nif`
  (new embedded Rust NIF, `native/hecate_rag_corpus_sync_nif/`, via
  `rustler` + `git2` with vendored libgit2): for every repo in
  `corpus_repos_config`, clones it if its local path doesn't exist yet
  (`clone_or_sync/3`), otherwise fetches `origin` for the checkout's
  current branch and fast-forwards it — every 2 minutes, entirely
  without an OS `git` binary at runtime, on the host or in the
  container. `--ff-only` in spirit — a diverged history is reported
  and left untouched, never merged. Replaces an external
  bash-script-on-a-systemd-timer design that assumed a single
  already-cloned checkout and was drafted but never deployed.
  `gitoxide`/`gix` was evaluated and rejected: no porcelain-level pull,
  only low-level pieces to assemble by hand.
- `scripts/build-corpus-sync-nif.sh` builds the new NIF; the
  `Containerfile`'s builder stage now runs it (previously only built
  NIFs for `_checkouts/`-overridden dependencies, never this repo's
  own `native/`) — verified against a real Alpine/musl container build,
  not just the local dev machine.
- `docker-compose.hecate-rag.yml` (in `macula-demo/infrastructure`):
  the old host-side pre-cloned `/corpus:ro` mount is replaced by a
  read-only mount of the new `corpus-repos.json`; `hecate-rag` now
  owns the clone itself.

### Changed

- `hecate_om` dependency bumped to 0.18.0 (was locked at 0.17.0; the
  existing `~> 0.17` constraint already permitted it). Purely additive
  on `hecate_om`'s side — no behavior change here.
- `relx`'s release version in `rebar.config` was still `"0.1.6"` despite
  `hecate_rag.app.src` and `hecate_rag_service:info/0` already reading
  `"0.1.7"` (missed in that release) — corrected alongside this
  release's own bump so the built release tarball's name matches.

### Fixed

- Two real bugs found live on beam03 after this version's own first
  deploy, both blocking `corpus_git_sync`/`refresh_corpus_scheduler`
  from ever doing useful work against the real corpus:
  - `hecate_rag_corpus_sync_nif` failed every tick with `"repository
    path '/corpus' is not owned by current user"` — libgit2's
    ownership-validation check (the CVE-2022-24765 mitigation) refusing
    a bind-mounted host directory whose owner UID doesn't match the
    container's runtime UID, exactly the situation for every path this
    NIF touches. Fixed by adding each path to `safe.directory` in the
    global git config (`Config::open_default()?.open_global()?.set_multivar(...)`,
    idempotent per path via a `Mutex<HashSet>` guard) rather than
    disabling the check process-wide — reproduced the exact failure and
    verified the fix in an isolated container before shipping it, not
    just the symptom. `git2::opts::set_verify_owner_validation(false)`
    also works and was tried first, but trusts every path this NIF will
    ever touch instead of only the ones it's actually configured for.
  - `refresh_corpus_scheduler` crash-looped indefinitely (every tick)
    with `{timeout, {gen_server, call, [rag_store, {get_watermark, ...}]}}`:
    `rag_store`'s default 5000ms `gen_server:call/2` timeout is too
    short once its single gen_server is legitimately busy running
    barrel's own record-mode embedding (a real mesh round-trip to the
    configured embedder, inside the same `handle_call` that stores the
    chunk) under a real write burst — an unrelated queued call, even a
    cheap read, times out waiting its turn, not because anything is
    actually stuck. Every `rag_store` public function now passes an
    explicit `?CALL_TIMEOUT` (60000ms) instead of the implicit default.

## [0.1.7] - 2026-09-01

### Changed

- All 15 mesh capabilities now advertise and dispatch through
  `hecate_om_capabilities:register/1` (via `hecate_rag_service:capabilities/0`'s
  own `handler` key and `hecate_om_simple_handler`) instead of
  `hecate_rag_mesh_rpc`'s own hand-rolled `macula:advertise/5` loop,
  which previously ran independently of, and redundantly with, the
  record-only advertisements `hecate_om:boot/1` was already publishing
  for the same 15 names. One registration path now, not two; gains
  org-scoped dual-registration, DHT publishing, and periodic
  re-advertise for free. Wire payloads are unchanged — verified against
  `hecate_om_simple_handler`'s own tests, which pin the exact
  `{ok, _}`-unwrapping behavior the old direct path had, and against
  this repo's own compile + dialyzer run against the real published
  dependency, not just a local checkout.
- Bumped `hecate_om` `~> 0.16` -> `~> 0.17` (`hecate_om_simple_handler`
  and `auth_opts/1`, both new there).
- No capability sets `auth` yet — all 15 stay open, unchanged behavior.
  `prune_chunks`/`schedule_reembed` are gating candidates, not decided;
  see `hecate-om/plans/PLAN_UCAN_GATED_CAPABILITIES.md`.

## [0.1.6] - 2026-09-01

### Changed
- Retired `mcp/` dev-loop tool (TypeScript MCP stdio server bridging
  Claude to hecate-rag via local HTTP). Superseded by the mesh API —
  agents with mesh access call `hecate-rag.upload_knowledge`,
  `add_knowledge`, `search_chunks_semantic`, etc. directly via
  `macula:call`, no HTTP bridge needed.
- Updated README: accurate capability count (15), fixed deps list
  (barrel not esqlite, no hecate-vector/hecate-embed as separate deps),
  fixed deploy section (watchtower/docker, not hecate-gitops), updated
  umbrella layout with all current desks.
- Updated `guides/architecture.md`: fixed topic filter typo.

## [0.1.5] - 2026-09-01

### Added
- **`upload_knowledge` capability**: raw file → chunk → embed → store,
  entirely server-side. The caller sends raw bytes; the server chunks
  via `markdown_chunker`, embeds via `rag_embedder` (in the caller's
  process, not inside `rag_store`'s gen_server), and writes each chunk
  with its vector. Mesh RPC + HTTP API.
- **`add_knowledge` capability**: text snippet → chunk → embed → store,
  for conversational deposits. Handles short text that the chunker
  would skip (under 80 bytes) by creating a single chunk directly.
  Optional `topics` field tags chunks after storing. Mesh RPC + HTTP API.
- `rag_embedder`: facade for embedding text outside the gen_server.
  Delegates to `rag_embed_hecate_embedder` (mesh) or `barrel_embed_ollama`
  (local), matching the existing provider config.
- `rag_chunk_embedder`: worker that embeds chunks via `rag_embedder`
  and writes to `rag_store:put_chunk_with_vector/4`.
- `rag_store:put_chunk_with_vector/4`: writes a chunk with a pre-computed
  `_embedding` vector. Barrel indexes it synchronously without calling
  the embedder — a fast barrel write + HNSW insert.

### Changed
- **`rag_store` no longer blocks on embedding.** Barrel's embedding
  policy now has `fields => []` — barrel never auto-embeds. All
  embedding is application-layer: callers compute vectors via
  `rag_embedder` and pass them to `put_chunk_with_vector/4`. The
  gen_server only does fast barrel reads/writes, never an outbound
  mesh call.
- **`rag_store:search_text/2`** is no longer a gen_server call. It
  embeds the query via `rag_embedder` in the caller's process, then
  delegates to `search_vector/2` (a fast gen_server call). This keeps
  the gen_server responsive even when the embedder is slow.
- Added `inets` and `ssl` to `hecate_rag.app.src` applications
  (required by `rag_topic_classifier`'s `httpc` calls).
- `knowledge_pipeline_SUITE`: 14 tests for upload_knowledge,
  add_knowledge, put_chunk_with_vector, store responsiveness, and
  mesh RPC routes.

## [0.1.4] - 2026-09-01

### Changed
- Picked up `hecate_om` 0.16.5 (already permitted by `~> 0.16`, no
  rebar.config change needed), which picks up `reckon_db` 5.11.1:
  `read_all_global/3` no longer re-scans and re-sorts the entire event
  store on every paginated catch-up call. Affects any store this
  service opens with real accumulated volume on restart.

## [0.1.3] - 2026-09-01

### Added
- **Topic classification**: new `classify_topics` capability (13th mesh
  procedure). Classifies a document's chunks into 1-5 topic labels via
  an LLM API (NVIDIA NIM, OpenAI-compatible, free tier). Two modes:
  `document` (1 API call, tags all chunks with the same set) and
  `per_chunk` (N calls, per-chunk precision).
- **Topic-filtered search**: `search_chunks_semantic` now accepts an
  optional `<<"topics">> => [binary()]` param. Over-fetches 3x `top_k`
  from the vector index, post-filters by topic intersection, returns
  `top_k` filtered results.
- `rag_store:tag_chunk/2` — merges topic labels into an existing chunk's
  barrel document (metadata-only write, no re-embed).
- `<<"topics">>` added to barrel's `metadata_fields` for indexing.
- NVIDIA NIM config (`topic_classifier`) in dev.config (enabled) and
  sys.config.src (enabled, key from `HECATE_TOPIC_API_KEY` env var).
- `classify_topics_SUITE`: 23 unit + integration tests (command
  validation, response parsing, storage, handler, search filter, mesh
  RPC route). E2E verified against the real NVIDIA API.
- `meck` added as a test-only dependency for mocking.

### Changed
- Switched HTTP client from `hackney` to `httpc` (Erlang/OTP built-in)
  for the topic classifier — hackney's TLS connection pool could not
  reach `integrate.api.nvidia.com` (`gen_statem connect` timeout).
- Bumped version to 0.1.3.

## [0.1.2] - 2026-08-31

### Changed
- Bumped `hecate_om` dependency `~> 0.10` -> `~> 0.16` (resolves 0.16.4).
  Was 6 minor versions behind; 0.16.1-0.16.3 add diagnostic logging for
  skipped capability advertisement (pool/keypair/realm) that would have
  made the v0.1.1 identity_key_path bug hunt immediate instead of hours.
- `cowboy` left at `~> 2.12.0` -- hecate_om's own `rebar.config` still
  pins cowboy `~> 2.12.0` even at 0.16.4 (hex latest is 2.18.0), and
  asking for newer here deadlocks rebar3's resolver (cowlib version
  conflict). Not fixable from this repo; flagged, not fixed.

## [0.1.1] - 2026-08-31

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
