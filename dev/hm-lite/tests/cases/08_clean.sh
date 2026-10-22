#!/usr/bin/env bash
#
# tests/cases/08_clean.sh - garbage collection behaviour.
#

TESTS=(
  test_clean_keeps_the_referenced_objects
  test_clean_removes_an_unreferenced_object
  test_clean_removes_the_unreferenced_rows
  test_clean_keeps_the_objects_of_an_old_generation
  test_clean_reports_a_missing_object
  test_clean_declining_changes_nothing
  test_clean_dry_run_changes_nothing
  test_clean_rejects_unknown_options
)

# _clean_fixture - a project with one generation and one content object.
_clean_fixture() {
  _test_setup clean_fixture
  printf 'hello\n' > "$SRC_DIR/a.txt"

  run_hm_input 'y
' add "$SRC_DIR/a.txt"
  run_hm_input 'y
' gen
}

test_clean_keeps_the_referenced_objects() {
  _clean_fixture

  run_hm clean

  assert_rc 0 "$HM_STATUS" "clean succeeds"
  assert_contains "$HM_OUTPUT" "no garbage" "the store is reported as clean"
  assert_count "1" "$(find "$STORE_DIR" -type f | wc -l)" "the object was kept"
  assert_sql "1" "SELECT COUNT(*) FROM files;" "the row was kept"
}

test_clean_removes_an_unreferenced_object() {
  _clean_fixture

  # The generation is removed directly, the object becomes garbage.
  sqlite3 "$HM_DIR/db.sqlite" 'PRAGMA foreign_keys = ON; DELETE FROM generations;'

  run_hm_input 'y
' clean

  assert_rc 0 "$HM_STATUS" "clean succeeds"
  assert_count "0" "$(find "$STORE_DIR" -type f | wc -l)" "the object was removed"
  assert_sql "0" "SELECT COUNT(*) FROM files;" "the row was removed"
}

test_clean_removes_the_unreferenced_rows() {
  _clean_fixture

  sqlite3 "$HM_DIR/db.sqlite" 'PRAGMA foreign_keys = ON; DELETE FROM generations;'
  rm -f -- "$STORE_DIR"/*/*

  run_hm_input 'y
' clean

  assert_rc 0 "$HM_STATUS" "clean succeeds"
  assert_sql "0" "SELECT COUNT(*) FROM files;" "the dangling row was removed"
  assert_contains "$HM_OUTPUT" "0 missing" "no missing object is reported"
}

test_clean_keeps_the_objects_of_an_old_generation() {
  _clean_fixture

  # A second generation reuses the same content.
  printf 'second\n' > "$SRC_DIR/b.txt"
  run_hm_input 'y
' add "$SRC_DIR/b.txt"
  run_hm_input 'y
' gen

  run_hm clean

  assert_rc 0 "$HM_STATUS" "clean succeeds"
  assert_count "2" "$(find "$STORE_DIR" -type f | wc -l)" "both objects were kept"
  assert_sql "2" "SELECT COUNT(*) FROM files;" "both rows were kept"
}

test_clean_reports_a_missing_object() {
  _clean_fixture
  local hash
  hash="$(sqlite3 "$HM_DIR/db.sqlite" 'SELECT hash FROM files LIMIT 1;')"

  rm -f -- "$STORE_DIR/${hash:0:2}/$hash"

  run_hm clean

  assert_rc 0 "$HM_STATUS" "clean succeeds"
  assert_contains "$HM_OUTPUT" "MISSING" "the missing object is reported"
  assert_contains "$HM_OUTPUT" "missing from the store" "the reason is explained"
  assert_sql "1" "SELECT COUNT(*) FROM files;" "the row of the missing object was kept"
}

test_clean_declining_changes_nothing() {
  _clean_fixture
  sqlite3 "$HM_DIR/db.sqlite" 'PRAGMA foreign_keys = ON; DELETE FROM generations;'

  run_hm_input 'n
' clean

  assert_rc 0 "$HM_STATUS" "declining is not an error"
  assert_contains "$HM_OUTPUT" "Cancelled" "the cancellation is reported"
  assert_count "1" "$(find "$STORE_DIR" -type f | wc -l)" "the object was kept"
  assert_sql "1" "SELECT COUNT(*) FROM files;" "the row was kept"
}

test_clean_dry_run_changes_nothing() {
  _clean_fixture
  sqlite3 "$HM_DIR/db.sqlite" 'PRAGMA foreign_keys = ON; DELETE FROM generations;'

  run_hm clean --dry-run

  assert_rc 0 "$HM_STATUS" "the dry run succeeds"
  assert_contains "$HM_OUTPUT" "REMOVE" "the preview shows the object"
  assert_count "1" "$(find "$STORE_DIR" -type f | wc -l)" "the object was kept"
}

test_clean_rejects_unknown_options() {
  _clean_fixture

  run_hm clean --bogus

  assert_rc 2 "$HM_STATUS" "an unknown option is a usage error"
}
