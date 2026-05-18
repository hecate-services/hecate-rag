-- Read-model table for projected source-document facts.
-- Owned by project_sources. Read by query_sources.

CREATE TABLE IF NOT EXISTS sources (
    source_id       TEXT PRIMARY KEY,
    source_path     TEXT NOT NULL,
    source_type     TEXT NOT NULL,
    bytes           INTEGER,
    sha256          TEXT,
    ingested_at_ms  INTEGER NOT NULL,
    last_modified_ms INTEGER,
    meta            TEXT  -- JSON
);

CREATE INDEX IF NOT EXISTS sources_by_path
    ON sources (source_path);
