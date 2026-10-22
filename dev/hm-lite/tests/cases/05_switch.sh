#!/usr/bin/env bash
#
# tests/cases/05_switch.sh - switch and discard behaviour.
#

TESTS=(
  test_switch_materializes_the_generation
  test_switch_mirrors_the_absolute_paths
  test_switch_replaces_the_previous_tree
  test_switch_records_the_selected_generation
  test_switch_restores_the_recorded_mode
  test_switch_does_not_touch_the_live_filesystem
  test_switch_fails_when_an_object_is_missing
  test_switch_rejects_an_unknown_generation
  test_switch_requires_a_generation_argument
  test_discard_copies_the_current_tree
  test_discard_replaces_the_testing_workspace
  test_discard_requires_a_switched_generation
  test_discard_does_not_touch_the_live_filesystem
)

# _switch_fixture - one generation with one file and one directory.
_switch_fixture() {
  _test_setup switch_fixture
  mkdir -p "$SRC_DIR/sub"
  printf 'hello\n' > "$SRC_DIR/sub/a.txt"

  run_hm_input 'y
' add "$SRC_DIR"
  run_hm_input 'y
' gen
}

test_switch_materializes_the_generation() {
  _switch_fixture

  run_hm switch 1

  assert_rc 0 "$HM_STATUS" "switch succeeds"
  assert_file_exists "$CURRENT_DIR$SRC_DIR/sub/a.txt" "the file was materialized"
  assert_file_content "$CURRENT_DIR$SRC_DIR/sub/a.txt" "hello" "the content is correct"
}

test_switch_mirrors_the_absolute_paths() {
  _switch_fixture

  run_hm switch 1

  assert_rc 0 "$HM_STATUS" "switch succeeds"
  assert_file_exists "$CURRENT_DIR$SRC_DIR" "the directory was materialized"
  assert_file_exists "$CURRENT_DIR$SRC_DIR/sub" "the sub directory was materialized"
  # The absolute path of the entry is appended to the runtime directory.
  assert_contains "$CURRENT_DIR$SRC_DIR/sub/a.txt" "$SRC_DIR" \
    "the absolute path is mirrored below current/"
}

test_switch_replaces_the_previous_tree() {
  _switch_fixture

  run_hm switch 1
  assert_rc 0 "$HM_STATUS" "the first switch succeeds"

  printf 'changed\n' > "$CURRENT_DIR$SRC_DIR/sub/a.txt"
  printf 'stale\n' > "$CURRENT_DIR/stale.txt"

  run_hm switch 1
  assert_rc 0 "$HM_STATUS" "the second switch succeeds"

  assert_file_absent "$CURRENT_DIR/stale.txt" "the old tree was removed"
  assert_file_content "$CURRENT_DIR$SRC_DIR/sub/a.txt" "hello" "the tree was restored"
}

test_switch_records_the_selected_generation() {
  _switch_fixture

  run_hm switch 1

  assert_rc 0 "$HM_STATUS" "switch succeeds"
  assert_sql "1" "SELECT value FROM state WHERE key = 'selected_generation';" \
    "the selected generation was recorded"
}

test_switch_restores_the_recorded_mode() {
  _test_setup switch_mode
  printf 'hello\n' > "$SRC_DIR/a.txt"
  chmod 640 -- "$SRC_DIR/a.txt"

  run_hm_input 'y
' add "$SRC_DIR/a.txt"
  run_hm_input 'y
' gen

  run_hm switch 1

  assert_rc 0 "$HM_STATUS" "switch succeeds"
  assert_eq "640" "$(stat -c '%a' -- "$CURRENT_DIR$SRC_DIR/a.txt")" \
    "the recorded mode was restored"
}

test_switch_does_not_touch_the_live_filesystem() {
  _switch_fixture
  local before after

  before="$(stat -c '%s %Y %a' -- "$SRC_DIR/sub/a.txt")"

  run_hm switch 1

  after="$(stat -c '%s %Y %a' -- "$SRC_DIR/sub/a.txt")"

  assert_eq "$before" "$after" "the source file was not modified"
  assert_file_content "$SRC_DIR/sub/a.txt" "hello" "the content of the source file is unchanged"
}

test_switch_fails_when_an_object_is_missing() {
  _switch_fixture
  local hash
  hash="$(sqlite3 "$HM_DIR/db.sqlite" 'SELECT hash FROM files LIMIT 1;')"

  rm -f -- "$HM_DIR/store/objects/${hash:0:2}/$hash"

  run_hm switch 1

  assert_rc 6 "$HM_STATUS" "switch fails with the store status"
  assert_file_absent "$CURRENT_DIR$SRC_DIR/sub/a.txt" "nothing was materialized"
}

test_switch_rejects_an_unknown_generation() {
  _switch_fixture

  run_hm switch 42

  assert_rc 4 "$HM_STATUS" "an unknown generation is a state error"
  assert_contains "$HM_OUTPUT" "no generation" "the error explains the problem"
}

test_switch_requires_a_generation_argument() {
  _switch_fixture

  run_hm switch

  assert_rc 2 "$HM_STATUS" "a missing argument is a usage error"
}

test_discard_copies_the_current_tree() {
  _switch_fixture

  run_hm switch 1
  assert_rc 0 "$HM_STATUS" "switch succeeds"

  run_hm discard

  assert_rc 0 "$HM_STATUS" "discard succeeds"
  assert_file_exists "$TESTING_DIR$SRC_DIR/sub/a.txt" "the tree was copied"
  assert_file_content "$TESTING_DIR$SRC_DIR/sub/a.txt" "hello" "the content is correct"
}

test_discard_replaces_the_testing_workspace() {
  _switch_fixture

  run_hm switch 1
  run_hm discard
  assert_rc 0 "$HM_STATUS" "the first discard succeeds"

  printf 'changed\n' > "$TESTING_DIR$SRC_DIR/sub/a.txt"
  printf 'stale\n' > "$TESTING_DIR/stale.txt"

  run_hm discard

  assert_rc 0 "$HM_STATUS" "the second discard succeeds"
  assert_file_absent "$TESTING_DIR/stale.txt" "the old content was removed"
  assert_file_content "$TESTING_DIR$SRC_DIR/sub/a.txt" "hello" "the content was restored"
}

test_discard_requires_a_switched_generation() {
  _switch_fixture

  run_hm discard

  assert_rc 4 "$HM_STATUS" "discard fails when no generation was switched"
  assert_contains "$HM_OUTPUT" "switch" "the error names the remedy"
}

test_discard_does_not_touch_the_live_filesystem() {
  _switch_fixture
  local before after

  run_hm switch 1
  before="$(stat -c '%s %Y %a' -- "$SRC_DIR/sub/a.txt")"

  run_hm discard

  after="$(stat -c '%s %Y %a' -- "$SRC_DIR/sub/a.txt")"

  assert_eq "$before" "$after" "the source file was not modified"
}
