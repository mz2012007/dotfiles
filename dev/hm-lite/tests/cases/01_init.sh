#!/usr/bin/env bash
#
# tests/cases/01_init.sh - initialisation behaviour.
#

TESTS=(
  test_init_creates_the_project
  test_init_is_idempotent
  test_init_keeps_existing_data
  test_init_creates_the_schema
  test_init_rejects_a_malformed_database
  test_init_reports_a_missing_schema
  test_init_rejects_a_file_as_project_directory
  test_init_rejects_arguments
  test_unknown_command_is_rejected
  test_help_is_available
  test_the_project_directory_does_not_depend_on_the_working_directory
)

test_init_creates_the_project() {
  _test_setup init_creates raw

  run_hm init

  assert_rc 0 "$HM_STATUS" "init succeeds"
  assert_file_exists "$HM_DIR/db.sqlite" "the database was created"
  assert_file_exists "$HM_DIR/config" "the configuration file was created"
  assert_file_exists "$HM_DIR/store/objects" "the content store was created"
  assert_file_exists "$HM_DIR/current" "the current directory was created"
  assert_file_exists "$HM_DIR/testing" "the testing directory was created"
  assert_file_exists "$HM_DIR/backup" "the backup directory was created"
  assert_file_exists "$HM_DIR/logs" "the log directory was created"
  assert_file_exists "$HM_DIR/tmp" "the temporary directory was created"
}

test_init_creates_the_schema() {
  _test_setup init_schema raw

  run_hm init
  assert_rc 0 "$HM_STATUS" "init succeeds"

  assert_sql "1" "PRAGMA user_version;" "the schema version is 1"
  assert_sql "7" \
    "SELECT COUNT(*) FROM sqlite_master WHERE type = 'table';" \
    "all seven tables were created"
  assert_sql "5" \
    "SELECT COUNT(*) FROM sqlite_master WHERE type = 'index' AND name LIKE 'idx_%';" \
    "the schema indexes were created"

  # The foreign key enforcement must be active on every connection, an
  # empty result means that no violation was found.
  assert_sql "" "PRAGMA foreign_key_check;" "the foreign key check is clean"
}

test_init_is_idempotent() {
  _test_setup init_idempotent raw

  run_hm init
  assert_rc 0 "$HM_STATUS" "the first init succeeds"

  run_hm init
  assert_rc 0 "$HM_STATUS" "the second init succeeds"
  assert_contains "$HM_OUTPUT" "already exists" "the second init reports the existing database"

  # A marker in the database must survive the second initialisation.
  sqlite3 "$HM_DIR/db.sqlite" "INSERT INTO schema_meta (key, value) VALUES ('marker', 'kept');"
  run_hm init
  assert_sql "kept" "SELECT value FROM schema_meta WHERE key = 'marker';" \
    "the second init did not touch the existing data"
}

test_init_keeps_existing_data() {
  _test_setup init_keeps raw

  run_hm init
  assert_rc 0 "$HM_STATUS" "init succeeds"

  sqlite3 "$HM_DIR/db.sqlite" \
    "INSERT INTO paths (path, kind, created_at) VALUES ('/tmp/keepme', 'file', 1);"

  run_hm init
  assert_rc 0 "$HM_STATUS" "init succeeds again"
  assert_sql "1" "SELECT COUNT(*) FROM paths WHERE path = '/tmp/keepme';" \
    "the existing path was not removed"
}

test_init_rejects_a_malformed_database() {
  _test_setup init_malformed raw

  mkdir -p -- "$HM_DIR"
  printf 'this is not a sqlite database\n' > "$HM_DIR/db.sqlite"

  run_hm init

  assert_rc 5 "$HM_STATUS" "init fails on a malformed database"
  assert_file_content "$HM_DIR/db.sqlite" "this is not a sqlite database" \
    "the malformed database was not overwritten"
}

test_init_reports_a_missing_schema() {
  _test_setup init_no_schema raw

  export HM_SCHEMA_FILE="$TEST_DIR/does-not-exist.sql"

  run_hm init

  assert_rc 3 "$HM_STATUS" "init fails when the schema file is missing"
  assert_contains "$HM_OUTPUT" "schema file" "the error mentions the schema file"
}

test_init_rejects_a_file_as_project_directory() {
  _test_setup init_file_target raw

  rm -rf -- "$HM_DIR"
  printf 'not a directory\n' > "$HM_DIR"

  run_hm init

  assert_rc 3 "$HM_STATUS" "init fails when the project path is a file"
}

test_init_rejects_arguments() {
  _test_setup init_arguments raw

  run_hm init --force

  assert_rc 2 "$HM_STATUS" "init rejects unknown arguments"
}

test_unknown_command_is_rejected() {
  _test_setup init_unknown raw

  run_hm bogus

  assert_rc 2 "$HM_STATUS" "an unknown command exits with the usage status"
  assert_contains "$HM_OUTPUT" "Unknown command" "the error names the unknown command"
}

test_help_is_available() {
  _test_setup init_help raw

  run_hm --help

  assert_rc 0 "$HM_STATUS" "help exits successfully"
  assert_contains "$HM_OUTPUT" "Usage: hm" "the usage text is printed"
}

test_the_project_directory_does_not_depend_on_the_working_directory() {
  _test_setup init_cwd raw

  run_hm init
  assert_rc 0 "$HM_STATUS" "init succeeds"

  local before after
  before="$(sqlite3 "$HM_DIR/db.sqlite" 'SELECT COUNT(*) FROM sqlite_master;')"

  cd "$DEST_DIR" || return 1
  run_hm init
  after="$(sqlite3 "$HM_DIR/db.sqlite" 'SELECT COUNT(*) FROM sqlite_master;')"

  assert_eq "$before" "$after" "the database is the same no matter where hm is called"
}
