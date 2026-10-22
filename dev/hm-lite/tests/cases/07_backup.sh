#!/usr/bin/env bash
#
# tests/cases/07_backup.sh - backup and restore behaviour.
#
# The test list is read by the runner, shellcheck only sees this
# file and therefore reports the variable as unused.
# shellcheck disable=SC2034

TESTS=(
  test_backup_creates_an_archive
  test_backup_holds_the_database_and_the_store
  test_backup_writes_a_checksum_manifest
  test_backup_is_consistent
  test_backup_rejects_unknown_arguments
  test_backup_rejects_the_yes_option
  test_restore_brings_the_state_back
  test_restore_validates_the_archive
  test_restore_refuses_a_damaged_archive
  test_restore_refuses_a_missing_file
  test_restore_declining_changes_nothing
)

# _backup_fixture - a project with one generation and one content object.
_backup_fixture() {
  _test_setup backup_fixture
  printf 'hello\n' > "$SRC_DIR/a.txt"

  run_hm_input 'y
' add "$SRC_DIR/a.txt"
  run_hm_input 'y
' gen
}

# _backup_archive - print the path of the archive that the last backup made.
_backup_archive() {
  local archive
  archive="$(find "$HM_DIR/backup" -name 'hm-backup-*.tar.gz' -type f | sort | tail -n 1)"
  printf '%s\n' "$archive"
}

test_backup_creates_an_archive() {
  _backup_fixture

  run_hm backup

  assert_rc 0 "$HM_STATUS" "backup succeeds"
  assert_file_exists "$(_backup_archive)" "the archive was created"
  assert_contains "$HM_OUTPUT" "Restore:" "the restore command is printed"
}

test_backup_holds_the_database_and_the_store() {
  _backup_fixture
  local archive

  run_hm backup
  archive="$(_backup_archive)"

  assert_rc 0 "$HM_STATUS" "backup succeeds"
  assert_contains "$(tar -tzf "$archive")" "db.sqlite" "the archive holds the database"
  assert_contains "$(tar -tzf "$archive")" "store/" "the archive holds the content store"
  assert_contains "$(tar -tzf "$archive")" "manifest.tsv" "the archive holds the manifest"
}

test_backup_writes_a_checksum_manifest() {
  _backup_fixture
  local archive stage

  run_hm backup
  archive="$(_backup_archive)"

  stage="$TEST_DIR/stage"
  mkdir -p "$stage"
  tar -xzf "$archive" -C "$stage"

  assert_file_exists "$stage/manifest.tsv" "the manifest was written"
  assert_contains "$(cat -- "$stage/manifest.tsv")" "db.sqlite" "the database is listed"
  assert_contains "$(cat -- "$stage/manifest.tsv")" "store/" "the store is listed"
}

test_backup_is_consistent() {
  _backup_fixture
  local archive stage

  run_hm backup
  archive="$(_backup_archive)"

  stage="$TEST_DIR/stage"
  mkdir -p "$stage"
  tar -xzf "$archive" -C "$stage"

  assert_sql "1" \
    "SELECT COUNT(*) FROM generations;" \
    "the restored database holds the generation"

  # The checksums of the archive must be verifiable with sha256sum.
  local verified
  verified="$(cd -- "$stage" && sha256sum -c --quiet -- manifest.tsv 2>&1)"
  assert_eq "" "$verified" "every file of the archive matches its checksum"
}

test_backup_rejects_unknown_arguments() {
  _backup_fixture

  run_hm backup --bogus

  assert_rc 2 "$HM_STATUS" "an unknown argument is a usage error"
}

test_backup_rejects_the_yes_option() {
  _backup_fixture

  # The backup never asks for a confirmation, an option that promises to
  # skip it would be a lie.
  run_hm backup --yes

  assert_rc 2 "$HM_STATUS" "the yes option is a usage error"
  assert_contains "$HM_OUTPUT" "Unknown argument" "the reason is named"
}

test_restore_brings_the_state_back() {
  _backup_fixture
  local archive

  run_hm backup
  archive="$(_backup_archive)"

  # The project changes after the backup was taken.
  printf 'changed\n' > "$SRC_DIR/a.txt"
  run_hm_input 'y
' add "$SRC_DIR/a.txt"
  run_hm_input 'y
' gen

  assert_sql "2" "SELECT COUNT(*) FROM generations;" "the project has two generations"

  run_hm_input 'y
' restore "$archive"

  assert_rc 0 "$HM_STATUS" "restore succeeds"
  assert_sql "1" "SELECT COUNT(*) FROM generations;" "the older state is back"
  assert_sql "0" "SELECT COUNT(*) FROM pending_paths;" "the pending set of the backup is back"
}

test_restore_validates_the_archive() {
  _backup_fixture
  local archive

  run_hm backup
  archive="$(_backup_archive)"

  run_hm_input 'y
' restore "$archive"

  assert_rc 0 "$HM_STATUS" "restore succeeds"
  assert_contains "$HM_OUTPUT" "Restore preview" "the preview is printed"
}

test_restore_refuses_a_damaged_archive() {
  _backup_fixture
  local archive stage

  run_hm backup
  archive="$(_backup_archive)"

  stage="$TEST_DIR/stage"
  mkdir -p "$stage"
  tar -xzf "$archive" -C "$stage"
  printf 'damaged\n' >> "$stage/db.sqlite"

  # Rebuild the archive with the damaged database.
  tar -czf "$archive.damaged" -C "$stage" db.sqlite store manifest.tsv meta.txt

  run_hm_input 'y
' restore "$archive.damaged"

  assert_rc 3 "$HM_STATUS" "a damaged archive is refused"
  assert_contains "$HM_OUTPUT" "damaged" "the reason is named"
}

test_restore_refuses_a_missing_file() {
  _backup_fixture

  run_hm_input 'y
' restore "$TEST_DIR/does-not-exist.tar.gz"

  assert_rc 3 "$HM_STATUS" "a missing backup file is refused"
  assert_contains "$HM_OUTPUT" "does not exist" "the reason is named"
}

test_restore_declining_changes_nothing() {
  _backup_fixture
  local archive

  run_hm backup
  archive="$(_backup_archive)"

  printf 'changed\n' > "$SRC_DIR/a.txt"
  run_hm_input 'y
' add "$SRC_DIR/a.txt"
  run_hm_input 'y
' gen

  run_hm_input 'n
' restore "$archive"

  assert_rc 7 "$HM_STATUS" "the decline is reported with its own exit code"
  assert_sql "2" "SELECT COUNT(*) FROM generations;" "the state was not changed"
}
