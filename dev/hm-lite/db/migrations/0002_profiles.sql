-- Migration 0002: profiles.
--
-- Moves every existing row into the default profile, so that a project
-- created before profiles existed keeps its state and its behaviour.
--
--   * every tracked path becomes a member of the default profile,
--   * the pending set and the generations are attached to the default
--     profile,
--   * the global selection is copied to the selection of the default
--     profile.
--
-- The content store is shared and needs no migration.

CREATE TABLE IF NOT EXISTS profiles (
    id         INTEGER PRIMARY KEY,
    name       TEXT    NOT NULL UNIQUE,
    created_at INTEGER NOT NULL
);

INSERT OR IGNORE INTO profiles (name, created_at)
VALUES ('default', CAST(strftime('%s', 'now') AS INTEGER));

CREATE TABLE IF NOT EXISTS path_profiles (
    path_id    INTEGER NOT NULL
               REFERENCES paths(id) ON DELETE CASCADE,
    profile_id INTEGER NOT NULL
               REFERENCES profiles(id) ON DELETE CASCADE,
    added_at   INTEGER NOT NULL,
    PRIMARY KEY (path_id, profile_id)
);

INSERT OR IGNORE INTO path_profiles (path_id, profile_id, added_at)
SELECT p.id, (SELECT id FROM profiles WHERE name = 'default'), p.created_at
  FROM paths p;

-- The pending set gains the profile. The table is small and nothing
-- references it, therefore it is rebuilt instead of renamed and copied
-- column by column.
CREATE TABLE pending_paths_v2 (
    path_id    INTEGER NOT NULL
               REFERENCES paths(id) ON DELETE CASCADE,
    profile_id INTEGER NOT NULL
               REFERENCES profiles(id) ON DELETE CASCADE,
    added_at   INTEGER NOT NULL,
    PRIMARY KEY (path_id, profile_id)
);

INSERT INTO pending_paths_v2 (path_id, profile_id, added_at)
SELECT pp.path_id, (SELECT id FROM profiles WHERE name = 'default'), pp.added_at
  FROM pending_paths pp;

DROP TABLE pending_paths;

ALTER TABLE pending_paths_v2 RENAME TO pending_paths;

CREATE INDEX IF NOT EXISTS idx_pending_added   ON pending_paths(added_at);
CREATE INDEX IF NOT EXISTS idx_pending_profile ON pending_paths(profile_id);
CREATE INDEX IF NOT EXISTS idx_path_profiles_profile ON path_profiles(profile_id);

-- A nullable column with a NULL default is the only form of ADD COLUMN
-- that SQLite accepts while foreign keys are enabled. Every row is
-- backfilled immediately, the code always writes the profile of a new
-- generation.
ALTER TABLE generations
ADD COLUMN profile_id INTEGER REFERENCES profiles(id) ON DELETE CASCADE;

UPDATE generations
   SET profile_id = (SELECT id FROM profiles WHERE name = 'default')
 WHERE profile_id IS NULL;

CREATE INDEX IF NOT EXISTS idx_generations_profile
    ON generations(profile_id, created_at DESC, id DESC);

INSERT OR REPLACE INTO state (key, value)
SELECT 'selected_generation:default', value
  FROM state
 WHERE key = 'selected_generation';

PRAGMA user_version = 2;
