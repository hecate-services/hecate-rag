# Changelog

Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Versioning: [SemVer](https://semver.org/).

## [Unreleased]

### Added
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

### Planned
- Wire `hecate_om_capabilities:publish/0` to actually advertise on
  the mesh bloom-channel once `macula:publish/4` is connected
- Register mesh RPC handlers for each capability via `macula:advertise/3`
- Real implementation in `maybe_*` handlers (today: validation + event-emit stubs)
- Projections: SQL `upsert` into `chunks` / `sources` tables on event arrival
- Query desks: actual `SELECT` + vector-search wiring

## [0.1.0] - YYYY-MM-DD

_Not yet released._
