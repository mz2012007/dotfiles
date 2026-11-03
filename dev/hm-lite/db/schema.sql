-- HM-Lite database schema.
--
-- This file is the single authoritative definition of the HM-Lite schema.
-- The shell code never contains a second copy of these statements, it only
-- applies this file.
--
-- Schema version 1.
--
-- Design notes:
--   * paths, content objects, generations and pending paths are four
--     different concepts and live in four different tables.
--   * a path is a location, it is not a content.
--   * a content object is identified by the SHA-256 hash of its bytes only.
--   * permissions, ownership and timestamps belong to the generation entry,
--     never to the shared content object.
--   * generation entries are never updated, a generation is immutable.

PRAGMA foreign_keys = ON;

-- --------------------------------------------------------------------------
-- Project metadata
-- --------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS schema_meta (
    key   TEXT PRIMARY KEY,
    value TEXT NOT NULL
);

-- --------------------------------------------------------------------------
-- Tracked paths
-- --------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS paths (
    id         INTEGER PRIMARY KEY,
    path       TEXT    NOT NULL UNIQUE,
    kind       TEXT    NOT NULL CHECK (kind IN ('file', 'dir')),
    created_at INTEGER NOT NULL
);

-- Paths that are selected for inclusion in the next generation.
CREATE TABLE IF NOT EXISTS pending_paths (
    path_id  INTEGER PRIMARY KEY
             REFERENCES paths(id) ON DELETE CASCADE,
    added_at INTEGER NOT NULL
);

-- --------------------------------------------------------------------------
-- Content objects
-- --------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS files (
    id         INTEGER PRIMARY KEY,
    hash       TEXT    NOT NULL UNIQUE CHECK (length(hash) = 64),
    size       INTEGER NOT NULL CHECK (size >= 0),
    created_at INTEGER NOT NULL
);

-- --------------------------------------------------------------------------
-- Generations
-- --------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS generations (
    id         INTEGER PRIMARY KEY,
    name       TEXT,
    comment    TEXT,
    created_at INTEGER NOT NULL,
    parent_id  INTEGER REFERENCES generations(id) ON DELETE SET NULL
);

-- The recorded state of a generation. One row per path.
CREATE TABLE IF NOT EXISTS generation_entries (
    generation_id INTEGER NOT NULL
                 REFERENCES generations(id) ON DELETE CASCADE,
    path_id       INTEGER NOT NULL
                 REFERENCES paths(id) ON DELETE CASCADE,
    file_id       INTEGER REFERENCES files(id) ON DELETE RESTRICT,
    entry_type    TEXT    NOT NULL CHECK (entry_type IN ('file', 'dir')),
    mode          INTEGER NOT NULL CHECK (mode >= 0 AND mode <= 4095),
    owner_uid     INTEGER NOT NULL,
    group_gid     INTEGER NOT NULL,
    mtime         INTEGER NOT NULL,
    size          INTEGER NOT NULL DEFAULT 0 CHECK (size >= 0),
    PRIMARY KEY (generation_id, path_id)
);

-- --------------------------------------------------------------------------
-- Project state (selected generation and similar pointers)
-- --------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS state (
    key   TEXT PRIMARY KEY,
    value TEXT
);

-- --------------------------------------------------------------------------
-- Indexes
-- --------------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_paths_kind        ON paths(kind);
CREATE INDEX IF NOT EXISTS idx_pending_added     ON pending_paths(added_at);
CREATE INDEX IF NOT EXISTS idx_entries_file      ON generation_entries(file_id);
CREATE INDEX IF NOT EXISTS idx_entries_path      ON generation_entries(path_id);
CREATE INDEX IF NOT EXISTS idx_generations_created ON generations(created_at DESC, id DESC);

-- --------------------------------------------------------------------------
-- Schema version
-- --------------------------------------------------------------------------
PRAGMA user_version = 1;
