-- Migration 0003: profile roots and local generation numbers.
--
--   * every existing profile keeps the historical unrestricted root "/",
--     because its paths were registered before roots existed,
--   * every generation receives a number inside its profile, ordered by
--     creation time and then by the internal id,
--   * the local sequence of every profile continues after its last number.
--
-- The content store is shared and needs no migration.

ALTER TABLE profiles
ADD COLUMN root TEXT NOT NULL DEFAULT '/';

ALTER TABLE profiles
ADD COLUMN next_generation_number INTEGER NOT NULL DEFAULT 1;

-- A nullable column is the only form of ADD COLUMN that SQLite accepts
-- without a constant default. Every row is backfilled immediately.
ALTER TABLE generations
ADD COLUMN number INTEGER;

UPDATE generations
   SET profile_id = (SELECT id FROM profiles WHERE name = 'default')
 WHERE profile_id IS NULL;

UPDATE generations
   SET number = (
     SELECT COUNT(*)
       FROM generations older
      WHERE older.profile_id = generations.profile_id
        AND (older.created_at < generations.created_at
             OR (older.created_at = generations.created_at
                 AND older.id <= generations.id))
   );

CREATE UNIQUE INDEX IF NOT EXISTS idx_generations_profile_number
    ON generations(profile_id, number);

UPDATE profiles
   SET next_generation_number = COALESCE(
     (SELECT MAX(g.number) + 1
        FROM generations g
       WHERE g.profile_id = profiles.id),
     1
   );

PRAGMA user_version = 3;
