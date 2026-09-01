# Plan: Verbatim retrieval + corpus freshness

**Status:** Phases 1-3 implemented and tested; not yet deployed (see
"Remaining before this is live on beam03").
**Created:** 2026-09-01
**Last Updated:** 2026-09-01
**Scope:** hecate-rag (this repo)

## End goal

An agent can fetch a document from `hecate-corpus` — a role definition, an
architecture doc — over the mesh, exact and byte-for-byte, and that content
stays current as the source file changes, with no human re-triggering
ingestion by hand.

## Classification

BUILD — retrieval plumbing and freshness automation, not a claim about the
world. Tests and a commit; no adversarial design gate.

## Relationship to `PLAN_RAG_MESH.md`

This plan does not re-scope or duplicate that one:
- Part A (seed job tracking, batch embedding) is an external prerequisite
  for a true whole-corpus reseed. Not re-scoped here — see "Prerequisite"
  below for the interim workaround.
- Part B Phase 4 ("Corpus merkle-root advertisement for staleness/integrity")
  is federation-level freshness across shards. Phase 3 below is the local,
  single-shard precursor that phase would need anyway.

## Prerequisite — seed reliability is not yet fixed

`PLAN_RAG_MESH.md` A1/A2 (job tracking for async seeds, batch embedding for
sync) have not shipped — no `job_id`/`seed/status` route or batch-embed path
exists in `CHANGELOG.md` or source. `maybe_seed_corpus.erl`'s sync path
already timed out past 31 and 111 files during that plan's own testing.
**Interim workaround for this plan's own work:** seed by directory
(`root_dir=/corpus/roles`, small globs) rather than one `/corpus` call, to
stay under the timeout. A genuine one-shot full-corpus reseed still needs
A1/A2 landed first — that is not this plan's job.

## Phase 1 — Verbatim source records for bulk-seeded docs — done

**Status: implemented and tested**
(`apps/embed_corpus/src/seed_corpus/maybe_seed_corpus.erl`,
`test/embed_corpus_SUITE.erl:seed_corpus_creates_verbatim_source`).
A real, pre-existing bug surfaced and was fixed in the same pass:
`RootDir ++ "/"` only strips the relative-path prefix correctly when
`RootDir` itself carries no trailing slash — a caller-supplied root
ending in `/` (Common Test's own `priv_dir` does; a caller could too)
doubled the slash, the prefix never matched, and every file's
`RelPath` (feeding both `document_id`/`source_path` and every chunk's
own `source_path`) silently became the full absolute path instead of
relative. No existing test exercised `seed_corpus` against a real
directory before this phase, so nothing had caught it.

`maybe_seed_corpus.erl`'s `ingest_file/3` → `store_chunk/2` only calls
`rag_store:put_chunk/3` per chunk (confirmed: zero calls to `upsert_source`
anywhere in this module). The per-document paths (`maybe_ingest_document.erl`,
`maybe_upload_knowledge.erl`) already call `rag_store:upsert_source/1`
correctly — this phase brings the bulk path to parity, not new machinery.

- Add one `rag_store:upsert_source/1` call per file in `ingest_file/3`,
  alongside the existing chunk loop.
- `document_id`: derived deterministically from the file's corpus-relative
  path, matching the existing position-derived `chunk_id` scheme in
  `markdown_chunker.erl` — re-seeding upserts the same source record rather
  than duplicating it, consistent with `put_doc_upsert`'s conflict-retry
  logic already handling this for chunks.
- `source_path`: the file's relative path (e.g. `roles/devops.md`).
- `raw_bytes`: the file's full original content — already read once per file
  by `markdown_chunker:chunk_file`; thread it through rather than
  re-reading the file.

**Files:** `apps/embed_corpus/src/seed_corpus/maybe_seed_corpus.erl`

## Phase 2 — Verbatim exact-fetch mesh RPC — done

**Status: implemented and tested**
(`get_document_verbatim` desk, `hecate_rag_mesh_rpc.erl`,
`hecate_rag_service.erl`, `test/embed_corpus_SUITE.erl:get_document_verbatim_round_trip`).
Capability count in `hecate_rag_service`'s own module doc updated
15 → 16 to match.

`rag_store:find_source_by_path/1` and `rag_store:get_source_content/1` both
already exist and work (used internally by `schedule_reembed` and
`embed_document`/`classify_topics` respectively) but neither is mesh-exposed.
`get_source_by_id` (which is mesh-exposed) returns only metadata
(`document_id`/`source_path`/`source_type`) — never `raw_bytes`.

- New capability, `hecate-rag.get_document_verbatim`: path in, composes
  `find_source_by_path/1` + `get_source_content/1`, returns
  `{source_path, raw_bytes}` or `{error, not_found}`.
- Wire into `hecate_rag_mesh_rpc.erl`: new `handle_get_document_verbatim/1`
  + `route/2` clause, following the exact shape every other handler already
  uses.
- New capability entry in `hecate_rag_service:capabilities/0`
  (`{hecate_om_simple_handler, {?MODULE, HandlerFun}}`, same as the rest).
- New QRY desk under `apps/query_sources/src/` (this is a read with no side
  effect, same department as `get_source_by_id`/`list_sources_page`, not a
  CMD op) — e.g. `get_document_verbatim/get_document_verbatim.erl`.
- **Not built:** the optional `GET /api/rag/source/verbatim?path=...` HTTP
  route for parity with the "Mesh RPC + HTTP API" dual-exposure pattern
  `answer_query`/`rerank_results` follow — skipped for this pass since
  the `macula-mcp` consumer only needs the mesh RPC; add later if an
  HTTP caller needs it.

**Files:** `src/hecate_rag_mesh_rpc.erl`, `src/hecate_rag_service.erl`,
`apps/query_sources/src/get_document_verbatim/get_document_verbatim.erl`
(new). CHANGELOG entry added (v0.1.8); README's Resources/Tools tables
not yet updated to mention `get_document_verbatim`.

## Phase 3 — Close the refresh_corpus loop — done

**Resolved: GitOps-style polling, two independent, uncoordinated loops**
(matching how `hecate-reconcile.timer` and watchtower already run on
this fleet with no direct signaling between them — eventual consistency
across both, not a push notification):

1. **Keeping `/corpus` current with git** — embedded in this application,
   not external infrastructure (superseding an earlier draft of this
   plan that put a bash script + systemd timer in `macula-demo`;
   removed, never enrolled anywhere). `hecate_rag_corpus_sync_nif`
   (new Rust crate, `native/hecate_rag_corpus_sync_nif/`, `rustler` +
   `git2` with `vendored-libgit2`) fetches `origin` for the checkout's
   current branch and fast-forwards it — no OS `git` binary needed at
   runtime, on the host or in the container. `--ff-only` in spirit: a
   real merge is never attempted, a diverged history is reported and
   left untouched, same safety property the earlier bash draft had.
   `corpus_git_sync` (new gen_server, `src/corpus_git_sync.erl`,
   supervised by `hecate_rag_sup` — service-level infrastructure, not
   `refresh_corpus`, since it calls a top-level app module and this
   umbrella's dependency direction runs from the top app into the
   sub-apps, never the reverse) ticks it every 2 minutes; `sync_now/0`
   is exported for an operator or a test to force one on demand.
   `gitoxide`/`gix` was evaluated and rejected first: it has no
   porcelain-level pull, only low-level `gix_protocol`/`gix_ref`/
   `gix_worktree_state`/`gix_revwalk` pieces to assemble by hand — real
   implementation risk for no benefit over the mature, complete `git2`
   API. Building the `.so`: `scripts/build-corpus-sync-nif.sh` (not
   wired into `rebar3 compile` — same reason rustler isn't a rebar dep,
   see `rebar.config`'s own note); needed once per release before
   `corpus_git_sync` can actually load it.
2. **Noticing `/corpus` changed and re-embedding** — application code,
   this repo. `refresh_corpus_scheduler` (new gen_server,
   `apps/refresh_corpus/src/refresh_corpus_scheduler.erl`, supervised by
   `refresh_corpus_sup`): ticks every 2 minutes, hashes every file under
   the configured corpus root (`corpus_root/0`, app env
   `hecate_rag.corpus_root`, defaulting to `/corpus`), and for anything
   `detect_corpus_change` reports as changed, records the request via
   `schedule_reembed` (kept for the observability trail its schema
   already provides) and immediately refreshes it: `upsert_source` with
   the file's current bytes, then `maybe_embed_document:embed` — which
   already re-reads whatever `upsert_source` just wrote, so one code
   path handles both a genuinely new file and a changed existing one.
   Immediate, not a separately-scheduled async drain: a markdown-sized
   re-ingest is cheap, so there's no real workload here needing
   detection decoupled from processing across a durable backlog (that
   remains a natural future addition if it ever is one, not built ahead
   of needing it). `scan/0` is exported so an operator or a test can
   force a rescan on demand, not just wait for the timer.

**Status: implemented and tested**
(`test/embed_corpus_SUITE.erl:refresh_scheduler_detects_and_refreshes_change`).
Two real bugs surfaced and were fixed in the same pass, both caught by
that test, neither by lint or compilation:
- The exact same trailing-slash relative-path bug Phase 1 fixed in
  `maybe_seed_corpus.erl` was independently reintroduced here (a fresh
  `relative_path/2` written the same way, same mistake) — fixed the
  same way, with the same comment explaining why.
- Both `maybe_detect_corpus_change:detect/1` and
  `maybe_schedule_reembed:schedule/1` take binary-keyed maps
  (`<<"corpus_id">>`, matching every command module's `from_map/1`
  convention) — this module's first draft called them with atom keys,
  which `from_map/1`'s pattern match silently doesn't match, falling
  through to a generic `missing_aggregate_id` that gave no hint the
  actual problem was the key type, not a missing field.

**Files:** `apps/refresh_corpus/src/refresh_corpus_scheduler.erl` (new),
`apps/refresh_corpus/src/refresh_corpus_sup.erl` (supervised child added),
`native/hecate_rag_corpus_sync_nif/{Cargo.toml,src/lib.rs}` (new),
`src/hecate_rag_corpus_sync_nif.erl` (new, NIF loader), `src/corpus_git_sync.erl`
(new, gen_server), `src/hecate_rag_sup.erl` (supervised child added),
`scripts/build-corpus-sync-nif.sh` (new), `rebar.config`/`.gitignore`
(notes + ignores for the native crate, matching `hecate_vector`'s
own convention).

Tested at three levels: the Rust crate's own `cargo test` (real local
git fixtures — up-to-date, fast-forward with a real working-tree
update, and a diverged-history case proving nothing gets overwritten;
gated behind `#[cfg(not(test))]` around the rustler wrapper, since
`enif_*` symbols only resolve once `dlopen`'d into a running BEAM, not
in a standalone test binary); the built `.so` actually exporting
`nif_init` (confirmed via `nm`); and a full Erlang-side integration
test (`test/hecate_rag_SUITE.erl:corpus_git_sync_fast_forwards`)
proving the NIF loads for real inside `hecate_rag` and
`corpus_git_sync`'s app-env override + gen_server plumbing work
end to end.

## Success criteria

- [x] Seeding `roles/` produces a `get_source_content`-readable verbatim
      record for every role file — proven against a fixture directory in
      `seed_corpus_creates_verbatim_source`; not yet run against the real
      `roles/` directory on beam03 (blocked on building+deploying a
      release carrying the NIF, and on `PLAN_RAG_MESH.md` A1/A2 for a
      genuine whole-corpus reseed).
- [x] `hecate-rag.get_document_verbatim({path: "roles/devops.md"})` returns
      content matching a local `sha256sum` of that file, byte-for-byte —
      proven via `get_document_verbatim_round_trip` against a per-document-ingested
      fixture; not yet run against the real deployed `roles/devops.md`.
- [x] Editing a role file and letting the refresh loop run (no manual
      curl) updates the stored verbatim content within one poll interval —
      proven via `refresh_scheduler_detects_and_refreshes_change` against a
      fixture directory. Real end-to-end proof on beam03 needs the
      `hecate-corpus-sync` systemd units enrolled (see Phase 3).
- [x] `PLAN_RAG_MESH.md` Part A stays tracked there; Part B Phase 4 stays
      unduplicated — this plan is its local prerequisite, not a replacement.

## Remaining before this is live on beam03

- [ ] Enroll `hecate-corpus-sync.{service,timer}` on beam03 (one-time,
      touches the box directly — see Phase 3).
- [ ] Push this repo's changes, let `hecate-reconcile.timer` deploy the
      new `hecate_rag` release carrying Phases 1-3.
- [ ] `PLAN_RAG_MESH.md` A1/A2 before attempting one real whole-corpus
      reseed (directory-by-directory seeding remains the interim path
      until then).
