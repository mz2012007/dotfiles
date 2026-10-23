#!/usr/bin/env bash
#
# tests/cases/16_profiles.sh - profile behaviour.
#
# A profile is an independent namespace for the tracked paths, the pending
# set, the generations and the selection. The content store stays shared.
# The test list is read by the runner, shellcheck only sees this file and
# therefore reports the variable as unused.
# shellcheck disable=SC2034

TESTS=(
  test_add_creates_the_profile_and_its_pending_set
  test_add_rejects_an_invalid_profile_name
  test_gen_requires_an_existing_profile
  test_gen_separates_the_pending_sets
  test_generations_are_separated_per_profile
  test_each_profile_has_its_own_parent
  test_the_same_path_can_belong_to_two_profiles
  test_the_default_profile_works_without_the_option
  test_list_filters_by_profile
  test_list_rejects_an_unknown_profile
  test_status_shows_the_comment_and_the_profile
  test_status_filters_by_profile
  test_status_rejects_an_unknown_profile
  test_switch_records_the_selection_per_profile
  test_show_prints_the_profile
  test_delete_refuses_a_generation_selected_in_any_profile
  test_apply_profile_uses_the_profile_selection
  test_apply_rejects_an_unknown_profile
  test_an_existing_v1_database_is_migrated
)

# _profiles_fixture - one generation in each of two profiles.
#
#   profile update-system: system.txt, generation 1
#   profile dev-env:       dev.txt,    generation 2
_profiles_fixture() {
  _test_setup profiles_fixture
  printf 'system\n' > "$SRC_DIR/system.txt"
  printf 'dev\n' > "$SRC_DIR/dev.txt"

  run_hm_input 'y\n' add --profile update-system "$SRC_DIR/system.txt"
  run_hm_input 'y\n' gen --profile update-system --name "system-1" --comment "system baseline"

  run_hm_input 'y\n' add --profile dev-env "$SRC_DIR/dev.txt"
  run_hm_input 'y\n' gen --profile dev-env --name "dev-1" --comment "dev baseline"
}

# _profiles_v1_schema - the historical schema version 1. It is embedded here
# so that the migration can be tested without keeping a copy of the old file
# in the project.
_profiles_v1_schema() {
  cat <<'SQL'
PRAGMA foreign_keys = ON;
CREATE TABLE schema_meta (key TEXT PRIMARY KEY, value TEXT NOT NULL);
CREATE TABLE paths (
    id INTEGER PRIMARY KEY,
    path TEXT NOT NULL UNIQUE,
    kind TEXT NOT NULL CHECK (kind IN ('file', 'dir')),
    created_at INTEGER NOT NULL
);
CREATE TABLE pending_paths (
    path_id INTEGER PRIMARY KEY REFERENCES paths(id) ON DELETE CASCADE,
    added_at INTEGER NOT NULL
);
CREATE TABLE files (
    id INTEGER PRIMARY KEY,
    hash TEXT NOT NULL UNIQUE CHECK (length(hash) = 64),
    size INTEGER NOT NULL CHECK (size >= 0),
    created_at INTEGER NOT NULL
);
CREATE TABLE generations (
    id INTEGER PRIMARY KEY,
    name TEXT,
    comment TEXT,
    created_at INTEGER NOT NULL,
    parent_id INTEGER REFERENCES generations(id) ON DELETE SET NULL
);
CREATE TABLE generation_entries (
    generation_id INTEGER NOT NULL REFERENCES generations(id) ON DELETE CASCADE,
    path_id INTEGER NOT NULL REFERENCES paths(id) ON DELETE CASCADE,
    file_id INTEGER REFERENCES files(id) ON DELETE RESTRICT,
    entry_type TEXT NOT NULL CHECK (entry_type IN ('file', 'dir')),
    mode INTEGER NOT NULL CHECK (mode >= 0 AND mode <= 4095),
    owner_uid INTEGER NOT NULL,
    group_gid INTEGER NOT NULL,
    mtime INTEGER NOT NULL,
    size INTEGER NOT NULL DEFAULT 0 CHECK (size >= 0),
    PRIMARY KEY (generation_id, path_id)
);
CREATE TABLE state (key TEXT PRIMARY KEY, value TEXT);
CREATE INDEX idx_paths_kind ON paths(kind);
CREATE INDEX idx_pending_added ON pending_paths(added_at);
CREATE INDEX idx_entries_file ON generation_entries(file_id);
CREATE INDEX idx_entries_path ON generation_entries(path_id);
CREATE INDEX idx_generations_created ON generations(created_at DESC, id DESC);
PRAGMA user_version = 1;
SQL
}

test_add_creates_the_profile_and_its_pending_set() {
  _test_setup profiles_add
  printf 'a\n' > "$SRC_DIR/a.txt"

  run_hm_input 'y\n' add --profile "update-system" "$SRC_DIR/a.txt"

  assert_rc 0 "$HM_STATUS" "add succeeds with a new profile"
  assert_sql "default" "SELECT name FROM profiles WHERE name = 'default';" \
    "the default profile exists"
  assert_sql "update-system" "SELECT name FROM profiles WHERE name = 'update-system';" \
    "the named profile was created"
  assert_sql "1" \
    "SELECT COUNT(*) FROM path_profiles x
       JOIN profiles pr ON pr.id = x.profile_id
      WHERE pr.name = 'update-system';" \
    "the path belongs to the profile"
  assert_sql "1" \
    "SELECT COUNT(*) FROM pending_paths pp
       JOIN profiles pr ON pr.id = pp.profile_id
      WHERE pr.name = 'update-system';" \
    "the path is pending in the profile"
  assert_sql "0" \
    "SELECT COUNT(*) FROM pending_paths pp
       JOIN profiles pr ON pr.id = pp.profile_id
      WHERE pr.name = 'default';" \
    "the default profile stays empty"
}

test_add_rejects_an_invalid_profile_name() {
  _test_setup profiles_invalid
  printf 'a\n' > "$SRC_DIR/a.txt"

  run_hm add --profile "bad name" "$SRC_DIR/a.txt"

  assert_rc 2 "$HM_STATUS" "an invalid profile name is a usage error"
  assert_contains "$HM_OUTPUT" "profile" "the error mentions the profile"
  assert_sql "0" "SELECT COUNT(*) FROM profiles WHERE name = 'bad name';" \
    "no profile was created"
  assert_sql "0" "SELECT COUNT(*) FROM paths;" "the path was not registered"
}

test_gen_requires_an_existing_profile() {
  _test_setup profiles_gen_unknown

  run_hm gen --profile "missing"

  assert_rc 3 "$HM_STATUS" "an unknown profile is a validation error"
  assert_contains "$HM_OUTPUT" "missing" "the error names the profile"
  assert_sql "0" "SELECT COUNT(*) FROM generations;" "no generation was created"
}

test_gen_separates_the_pending_sets() {
  _test_setup profiles_pending
  printf 'a\n' > "$SRC_DIR/a.txt"
  printf 'b\n' > "$SRC_DIR/b.txt"

  run_hm_input 'y\n' add --profile alpha "$SRC_DIR/a.txt"
  run_hm_input 'y\n' add --profile beta "$SRC_DIR/b.txt"
  assert_sql "2" "SELECT COUNT(*) FROM pending_paths;" "both profiles have a pending path"

  run_hm_input 'y\n' gen --profile alpha

  assert_rc 0 "$HM_STATUS" "gen succeeds for the profile"
  assert_sql "1" "SELECT COUNT(*) FROM generations;" "one generation was created"
  assert_sql "alpha" \
    "SELECT pr.name FROM generations g JOIN profiles pr ON pr.id = g.profile_id;" \
    "the generation belongs to the profile"
  assert_sql "1" "SELECT COUNT(*) FROM pending_paths;" \
    "only the pending path of the profile was cleared"
  assert_sql "beta" \
    "SELECT pr.name FROM pending_paths pp JOIN profiles pr ON pr.id = pp.profile_id;" \
    "the other profile keeps its pending path"
}

test_generations_are_separated_per_profile() {
  _profiles_fixture

  assert_sql "2" "SELECT COUNT(*) FROM generations;" "two generations exist"
  assert_sql "update-system" \
    "SELECT pr.name FROM generations g JOIN profiles pr ON pr.id = g.profile_id WHERE g.id = 1;" \
    "the first generation belongs to the first profile"
  assert_sql "dev-env" \
    "SELECT pr.name FROM generations g JOIN profiles pr ON pr.id = g.profile_id WHERE g.id = 2;" \
    "the second generation belongs to the second profile"
  assert_sql "1" \
    "SELECT number FROM generations g JOIN profiles pr ON pr.id = g.profile_id WHERE g.id = 1;" \
    "the first local generation is number one"
  assert_sql "1" \
    "SELECT number FROM generations g JOIN profiles pr ON pr.id = g.profile_id WHERE g.id = 2;" \
    "the second local generation is also number one"
  assert_sql "" "SELECT COALESCE(parent_id, '') FROM generations WHERE id = 2;" \
    "the second profile does not inherit the first profile parent"
}

test_each_profile_has_its_own_parent() {
  _profiles_fixture
  printf 'system two\n' > "$SRC_DIR/system2.txt"

  run_hm_input 'y\n' add --profile update-system "$SRC_DIR/system2.txt"
  run_hm_input 'y\n' gen --profile update-system

  assert_rc 0 "$HM_STATUS" "the second generation of the profile succeeds"
  assert_sql "1" "SELECT parent_id FROM generations WHERE id = 3;" \
    "the parent is the newest generation of the same profile"
  assert_sql "2" "SELECT number FROM generations WHERE id = 3;" \
    "the second generation has the local number two"
  assert_sql "2" \
    "SELECT COUNT(*) FROM generation_entries WHERE generation_id = 3;" \
    "the profile carries its own paths forward"
}

test_the_same_path_can_belong_to_two_profiles() {
  _test_setup profiles_shared
  printf 'shared\n' > "$SRC_DIR/shared.txt"

  run_hm_input 'y\n' add --profile alpha "$SRC_DIR/shared.txt"
  run_hm_input 'y\n' gen --profile alpha
  run_hm_input 'y\n' add --profile beta "$SRC_DIR/shared.txt"
  run_hm_input 'y\n' gen --profile beta

  assert_rc 0 "$HM_STATUS" "both generations succeed"
  assert_sql "2" \
    "SELECT COUNT(*) FROM path_profiles x
      WHERE x.path_id = (SELECT id FROM paths WHERE path = '$SRC_DIR/shared.txt');" \
    "the path is a member of both profiles"
  assert_sql "2" "SELECT COUNT(*) FROM generations;" "each profile has a generation"
  assert_sql "2" "SELECT COUNT(*) FROM generation_entries;" "each generation has the entry"
}

test_the_default_profile_works_without_the_option() {
  _test_setup profiles_default
  printf 'a\n' > "$SRC_DIR/a.txt"

  run_hm_input 'y\n' add "$SRC_DIR/a.txt"
  run_hm_input 'y\n' gen

  assert_rc 0 "$HM_STATUS" "the command works without a profile"
  assert_sql "default" \
    "SELECT pr.name FROM generations g JOIN profiles pr ON pr.id = g.profile_id;" \
    "the generation belongs to the default profile"
  assert_sql "1" \
    "SELECT COUNT(*) FROM path_profiles x
       JOIN profiles pr ON pr.id = x.profile_id
      WHERE pr.name = 'default';" \
    "the path belongs to the default profile"
}

test_list_filters_by_profile() {
  _profiles_fixture

  run_hm list

  assert_rc 0 "$HM_STATUS" "list succeeds"
  assert_contains "$HM_OUTPUT" "PROFILE" "the profile column is printed"
  assert_contains "$HM_OUTPUT" "system-1" "the first profile generation is listed"
  assert_contains "$HM_OUTPUT" "dev-1" "the second profile generation is listed"

  run_hm list --profile update-system

  assert_rc 0 "$HM_STATUS" "list succeeds with a profile"
  assert_contains "$HM_OUTPUT" "system-1" "the selected profile generation is listed"
  assert_not_contains "$HM_OUTPUT" "dev-1" "the other profile is filtered out"
}

test_list_rejects_an_unknown_profile() {
  _profiles_fixture

  run_hm list --profile "missing"

  assert_rc 3 "$HM_STATUS" "an unknown profile is a validation error"
  assert_contains "$HM_OUTPUT" "missing" "the error names the profile"
}

test_status_shows_the_comment_and_the_profile() {
  _profiles_fixture

  run_hm status

  assert_rc 0 "$HM_STATUS" "status succeeds"
  assert_contains "$HM_OUTPUT" "PROFILE" "the profile column is printed"
  assert_contains "$HM_OUTPUT" "COMMENT" "the comment column is printed"
  assert_contains "$HM_OUTPUT" "system baseline" "the comment is printed"
  assert_contains "$HM_OUTPUT" "update-system" "the profile name is printed"
}

test_status_filters_by_profile() {
  _profiles_fixture

  run_hm status --profile update-system

  assert_rc 0 "$HM_STATUS" "status succeeds with a profile"
  assert_contains "$HM_OUTPUT" "system baseline" "the selected profile comment is printed"
  assert_not_contains "$HM_OUTPUT" "dev baseline" "the other profile comment is filtered out"
  assert_not_contains "$HM_OUTPUT" "dev-env" "the other profile is filtered out"
}

test_status_rejects_an_unknown_profile() {
  _profiles_fixture

  run_hm status --profile "missing"

  assert_rc 3 "$HM_STATUS" "an unknown profile is a validation error"
  assert_contains "$HM_OUTPUT" "missing" "the error names the profile"
}

test_switch_records_the_selection_per_profile() {
  _profiles_fixture

  run_hm switch --profile update-system 1
  assert_rc 0 "$HM_STATUS" "switch succeeds for the first profile"
  assert_sql "1" "SELECT value FROM state WHERE key = 'selected_generation:update-system';" \
    "the selection of the first profile was recorded"
  assert_sql "1" "SELECT value FROM state WHERE key = 'selected_generation';" \
    "the global selection was recorded"

  run_hm switch --profile dev-env 1
  assert_rc 0 "$HM_STATUS" "switch succeeds for the second profile"
  assert_sql "2" "SELECT value FROM state WHERE key = 'selected_generation:dev-env';" \
    "the selection of the second profile was recorded"
  assert_sql "1" "SELECT value FROM state WHERE key = 'selected_generation:update-system';" \
    "the selection of the first profile was kept"
}

test_show_prints_the_profile() {
  _profiles_fixture

  run_hm show --profile update-system 1

  assert_rc 0 "$HM_STATUS" "show succeeds"
  assert_contains "$HM_OUTPUT" "Profile:" "the profile field is printed"
  assert_contains "$HM_OUTPUT" "update-system" "the profile name is printed"
}

test_delete_refuses_a_generation_selected_in_any_profile() {
  _profiles_fixture

  run_hm switch --profile update-system 1
  run_hm switch --profile dev-env 1

  run_hm delete --profile update-system 1 --yes

  assert_rc 3 "$HM_STATUS" "a generation selected in any profile is refused"
  assert_contains "$HM_OUTPUT" "selected generation" "the error explains the rule"
  assert_sql "1" "SELECT COUNT(*) FROM generations WHERE id = 1;" "the generation is kept"
}

test_apply_profile_uses_the_profile_selection() {
  _profiles_fixture

  run_hm switch --profile update-system 1
  run_hm switch --profile dev-env 1

  run_hm apply --profile update-system --dry-run

  assert_rc 0 "$HM_STATUS" "the dry run succeeds"
  assert_contains "$HM_OUTPUT" "$SRC_DIR/system.txt" "the selected generation of the profile is previewed"
  assert_not_contains "$HM_OUTPUT" "$SRC_DIR/dev.txt" "the other profile is not previewed"
}

test_apply_rejects_an_unknown_profile() {
  _profiles_fixture

  run_hm apply --profile "missing" --dry-run

  assert_rc 3 "$HM_STATUS" "an unknown profile is a validation error"
  assert_contains "$HM_OUTPUT" "missing" "the error names the profile"
}

test_an_existing_v1_database_is_migrated() {
  _test_setup profiles_migration raw

  _profiles_v1_schema | sqlite3 "$HM_DIR/db.sqlite"
  sqlite3 "$HM_DIR/db.sqlite" "
    INSERT INTO paths (path, kind, created_at) VALUES ('$SRC_DIR/a.txt', 'file', 1);
    INSERT INTO pending_paths (path_id, added_at) VALUES (1, 2);
    INSERT INTO generations (id, name, comment, created_at) VALUES (1, 'old', 'old comment', 3);
    INSERT INTO state (key, value) VALUES ('selected_generation', '1');"

  run_hm init

  assert_rc 0 "$HM_STATUS" "init migrates the database"
  assert_sql "3" "PRAGMA user_version;" "the schema version was raised"
  assert_sql "default" "SELECT name FROM profiles;" "the default profile was created"
  assert_sql "/" "SELECT root FROM profiles WHERE name = 'default';" \
    "the migrated profile keeps an unrestricted root"
  assert_sql "1" "SELECT profile_id FROM pending_paths;" \
    "the pending path moved to the default profile"
  assert_sql "1" "SELECT profile_id FROM generations WHERE id = 1;" \
    "the generation moved to the default profile"
  assert_sql "1" \
    "SELECT number FROM generations WHERE id = 1;" \
    "the legacy generation became local number one"
  assert_sql "2" \
    "SELECT next_generation_number FROM profiles WHERE name = 'default';" \
    "the migrated sequence continues after the existing generation"
  assert_sql "1" "SELECT COUNT(*) FROM path_profiles;" \
    "the tracked path is a member of the default profile"
  assert_sql "1" "SELECT value FROM state WHERE key = 'selected_generation:default';" \
    "the selection was copied to the default profile"
}
