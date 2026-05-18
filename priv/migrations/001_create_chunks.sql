-- Read-model table for projected chunk facts.
-- Owned by project_chunks. Read by query_chunks.

CREATE TABLE IF NOT EXISTS chunks (
    chunk_id        TEXT PRIMARY KEY,
    document_id     TEXT NOT NULL,
    source_path     TEXT,
    content         TEXT NOT NULL,
    content_hash    TEXT,
    headings        TEXT,   -- JSON array
    model_id        TEXT NOT NULL,
    dim             INTEGER NOT NULL,
    vector_ref      TEXT,   -- opaque id into hecate_vector
    embedded_at_ms  INTEGER NOT NULL,
    pruned_at_ms    INTEGER
);

CREATE INDEX IF NOT EXISTS chunks_by_document
    ON chunks (document_id);

CREATE INDEX IF NOT EXISTS chunks_by_source_path
    ON chunks (source_path);
