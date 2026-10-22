#!/usr/bin/env bash
#
# tests/cases/03_gen.sh - generation behaviour.
#
# The test list is read by the runner, shellcheck only sees this
# file and therefore reports the variable as unused.
# shellcheck disable=SC2034

TESTS=(
  test_gen_creates_a_generation
  test_gen_stores_the_content_object
  test_gen_records_the_metadata
  test_gen_records_directories
  test_gen_clears_the_pending_set
  test_gen_without_pending_paths_does_nothing
  test_gen_fails_when_a_pending_path_vanished
  test_gen_keeps_the_pending_set_after_a_failure
  test_gen_reuses_an_identical_content_object
  test_gen_carries_the_previous_paths_forward
  test_gen_does_not_modify_the_source_files
  test_gen_handles_special_file_names
  test_gen_declining_changes_nothing
  test_gen_rejects_unknown_options
  test_gen_requires_an_initialized_project
)

# _gen_add PATH - register a path and create the first generation.
_gen_add() {
  run_hm_input 'y
' add "$@"
  run_hm_input 'y
' gen
}

test_gen_creates_a_generation() {
  _test_setup gen_basic
  printf 'hello\n' > "$SRC_DIR/a.txt"

  _gen_add "$SRC_DIR/a.txt"

  assert_rc 0 "$HM_STATUS" "gen succeeds"
  assert_sql "1" "SELECT COUNT(*) FROM generations;" "a generation was created"
  assert_sql "1" "SELECT COUNT(*) FROM generation_entries;" "the generation has one entry"
  assert_sql "1" "SELECT COUNT(*) FROM files;" "one content object was recorded"
}

test_gen_stores_the_content_object() {
  _test_setup gen_store
  printf 'hello\n' > "$SRC_DIR/a.txt"
  local expected

  expected="$(sha256sum -- "$SRC_DIR/a.txt" | cut -d' ' -f1)"

  _gen_add "$SRC_DIR/a.txt"

  assert_rc 0 "$HM_STATUS" "gen succeeds"
  assert_sql "$expected" "SELECT hash FROM files;" "the hash was recorded"
  assert_file_exists "$HM_DIR/store/objects/${expected:0:2}/$expected" \
    "the content object was written to the store"
  assert_file_content "$HM_DIR/store/objects/${expected:0:2}/$expected" "hello" \
    "the stored object holds the original content"
}

test_gen_records_the_metadata() {
  _test_setup gen_meta
  printf 'hello\n' > "$SRC_DIR/a.txt"
  chmod 640 -- "$SRC_DIR/a.txt"

  _gen_add "$SRC_DIR/a.txt"

  assert_rc 0 "$HM_STATUS" "gen succeeds"
  assert_sql "416" "SELECT mode FROM generation_entries;" "the mode was recorded as a decimal"
  assert_sql "6" "SELECT size FROM generation_entries;" "the size was recorded"
  assert_sql "$(id -u)" "SELECT owner_uid FROM generation_entries;" "the owner was recorded"
  assert_sql "$(id -g)" "SELECT group_gid FROM generation_entries;" "the group was recorded"
}

test_gen_records_directories() {
  _test_setup gen_dirs
  mkdir -p "$SRC_DIR/sub"
  printf 'a\n' > "$SRC_DIR/sub/a.txt"

  _gen_add "$SRC_DIR"

  assert_rc 0 "$HM_STATUS" "gen succeeds"
  assert_sql "2" "SELECT COUNT(*) FROM generation_entries WHERE entry_type = 'dir';" \
    "the two directories were recorded"
  assert_sql "1" "SELECT COUNT(*) FROM generation_entries WHERE entry_type = 'file';" \
    "the file was recorded"
  assert_sql "0" "SELECT COUNT(*) FROM generation_entries WHERE entry_type = 'dir' AND file_id IS NOT NULL;" \
    "a directory has no content object"
}

test_gen_clears_the_pending_set() {
  _test_setup gen_pending
  printf 'a\n' > "$SRC_DIR/a.txt"

  _gen_add "$SRC_DIR/a.txt"

  assert_sql "0" "SELECT COUNT(*) FROM pending_paths;" "the pending set was cleared"
}

test_gen_without_pending_paths_does_nothing() {
  _test_setup gen_empty

  run_hm gen

  assert_rc 0 "$HM_STATUS" "gen succeeds without pending paths"
  assert_contains "$HM_OUTPUT" "no pending paths" "the command explains the situation"
  assert_sql "0" "SELECT COUNT(*) FROM generations;" "no generation was created"
}

test_gen_fails_when_a_pending_path_vanished() {
  _test_setup gen_vanished
  printf 'a\n' > "$SRC_DIR/a.txt"

  run_hm_input 'y
' add "$SRC_DIR/a.txt"
  assert_rc 0 "$HM_STATUS" "add succeeds"

  rm -f -- "$SRC_DIR/a.txt"

  run_hm gen

  assert_rc 4 "$HM_STATUS" "gen fails with the state status"
  assert_contains "$HM_OUTPUT" "does not exist any more" "the vanished path is named"
  assert_sql "0" "SELECT COUNT(*) FROM generations;" "no generation was created"
  assert_sql "1" "SELECT COUNT(*) FROM pending_paths;" "the pending set was not changed"
}

test_gen_keeps_the_pending_set_after_a_failure() {
  _test_setup gen_failure
  printf 'a\n' > "$SRC_DIR/a.txt"
  printf 'b\n' > "$SRC_DIR/locked.txt"

  run_hm_input 'y
' add "$SRC_DIR"
  assert_rc 0 "$HM_STATUS" "add succeeds"

  # A file that cannot be read makes the capture fail.
  chmod 000 -- "$SRC_DIR/locked.txt"

  run_hm gen

  chmod 644 -- "$SRC_DIR/locked.txt"

  assert_rc 9 "$HM_STATUS" "gen fails with the input/output status"
  assert_sql "0" "SELECT COUNT(*) FROM generations;" "no generation was created"
  assert_sql "3" "SELECT COUNT(*) FROM pending_paths;" "the pending set was not changed"
}

test_gen_reuses_an_identical_content_object() {
  _test_setup gen_dedup
  printf 'same\n' > "$SRC_DIR/a.txt"
  printf 'same\n' > "$SRC_DIR/b.txt"

  _gen_add "$SRC_DIR"

  assert_rc 0 "$HM_STATUS" "gen succeeds"
  assert_sql "1" "SELECT COUNT(*) FROM files;" "the identical content is stored once"
  assert_sql "3" "SELECT COUNT(*) FROM generation_entries;" "the directory and both files were recorded"
  assert_count "1" "$(find "$HM_DIR/store/objects" -type f | wc -l)" \
    "the store holds a single object"
}

test_gen_carries_the_previous_paths_forward() {
  _test_setup gen_carry
  printf 'a\n' > "$SRC_DIR/a.txt"

  _gen_add "$SRC_DIR/a.txt"
  assert_rc 0 "$HM_STATUS" "the first generation succeeds"
  assert_sql "1" "SELECT COUNT(*) FROM generation_entries WHERE generation_id = 1;" \
    "the first generation holds one entry"

  printf 'b\n' > "$SRC_DIR/b.txt"
  run_hm_input 'y
' add "$SRC_DIR/b.txt"
  run_hm_input 'y
' gen

  assert_rc 0 "$HM_STATUS" "the second generation succeeds"
  assert_sql "2" "SELECT COUNT(*) FROM generation_entries WHERE generation_id = 2;" \
    "the second generation holds both paths"
  assert_sql "1" "SELECT COUNT(*) FROM generations WHERE parent_id = 1;" \
    "the second generation points at its parent"
}

test_gen_does_not_modify_the_source_files() {
  _test_setup gen_nomodify
  printf 'original\n' > "$SRC_DIR/a.txt"
  local before after

  before="$(stat -c '%s %Y %a' -- "$SRC_DIR/a.txt")"

  _gen_add "$SRC_DIR/a.txt"

  after="$(stat -c '%s %Y %a' -- "$SRC_DIR/a.txt")"

  assert_eq "$before" "$after" "the source file was not modified"
  assert_file_content "$SRC_DIR/a.txt" "original" "the content of the source file is unchanged"
}

test_gen_handles_special_file_names() {
  _test_setup gen_special
  printf 'a\n' > "$SRC_DIR/with space.txt"
  printf 'b\n' > "$SRC_DIR/with'quote.txt"
  printf 'c\n' > "$SRC_DIR/with
newline.txt"

  _gen_add "$SRC_DIR"

  assert_rc 0 "$HM_STATUS" "gen succeeds with special file names"
  assert_sql "3" "SELECT COUNT(*) FROM generation_entries WHERE entry_type = 'file';" \
    "all three files were captured"
  assert_sql "3" "SELECT COUNT(*) FROM files;" "every file got its own content object"
}

test_gen_declining_changes_nothing() {
  _test_setup gen_decline
  printf 'a\n' > "$SRC_DIR/a.txt"

  run_hm_input 'y
' add "$SRC_DIR/a.txt"
  assert_rc 0 "$HM_STATUS" "add succeeds"

  run_hm_input 'n
' gen

  assert_rc 7 "$HM_STATUS" "the decline is reported with its own exit code"
  assert_contains "$HM_OUTPUT" "Cancelled" "the cancellation is reported"
  assert_sql "0" "SELECT COUNT(*) FROM generations;" "no generation was created"
  assert_sql "1" "SELECT COUNT(*) FROM pending_paths;" "the pending set was not changed"
}

test_gen_rejects_unknown_options() {
  _test_setup gen_options

  run_hm gen --bogus

  assert_rc 2 "$HM_STATUS" "an unknown option is a usage error"
}

test_gen_requires_an_initialized_project() {
  _test_setup gen_uninit raw

  run_hm gen

  assert_rc 3 "$HM_STATUS" "gen fails on an uninitialized project"
  assert_contains "$HM_OUTPUT" "not initialized" "the error explains the problem"
}
