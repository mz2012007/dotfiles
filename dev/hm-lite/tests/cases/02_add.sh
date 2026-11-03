#!/usr/bin/env bash
#
# tests/cases/02_add.sh - registration behaviour.
#

TESTS=(
  test_add_registers_a_single_file
  test_add_registers_a_directory_recursively
  test_add_handles_nested_directories
  test_add_deduplicates_overlapping_arguments
  test_add_reports_an_existing_path
  test_add_handles_special_file_names
  test_add_rejects_a_missing_path
  test_add_rejects_a_symbolic_link_argument
  test_add_skips_symbolic_links_inside_a_directory
  test_add_does_not_touch_the_content_store
  test_add_does_not_create_a_generation
  test_add_does_not_modify_the_source_files
  test_add_declining_changes_nothing
  test_add_requires_an_argument
  test_add_refresh_prunes_vanished_paths
)

test_add_registers_a_single_file() {
  _test_setup add_single
  printf 'content\n' > "$SRC_DIR/one.txt"

  run_hm_input 'y
' add "$SRC_DIR/one.txt"

  assert_rc 0 "$HM_STATUS" "add succeeds"
  assert_sql "1" "SELECT COUNT(*) FROM paths WHERE path = '$SRC_DIR/one.txt';" \
    "the file was registered"
  assert_sql "file" "SELECT kind FROM paths WHERE path = '$SRC_DIR/one.txt';" \
    "the kind of the path is file"
  assert_sql "1" "SELECT COUNT(*) FROM pending_paths;" "the path is pending"
}

test_add_registers_a_directory_recursively() {
  _test_setup add_dir
  mkdir -p "$SRC_DIR/sub/deep"
  printf 'a\n' > "$SRC_DIR/a.txt"
  printf 'b\n' > "$SRC_DIR/sub/b.txt"
  printf 'c\n' > "$SRC_DIR/sub/deep/c.txt"

  run_hm_input 'y
' add "$SRC_DIR"

  assert_rc 0 "$HM_STATUS" "add succeeds"
  assert_sql "6" "SELECT COUNT(*) FROM paths;" \
    "the directory, two sub directories and three files were registered"
  assert_sql "1" "SELECT COUNT(*) FROM paths WHERE path = '$SRC_DIR/sub/deep/c.txt';" \
    "the deeply nested file was registered"
  assert_sql "3" "SELECT COUNT(*) FROM paths WHERE kind = 'dir';" \
    "the directories were registered as directories"
}

test_add_handles_nested_directories() {
  _test_setup add_nested
  mkdir -p "$SRC_DIR/a/b/c"
  printf 'x\n' > "$SRC_DIR/a/b/c/file.txt"

  run_hm_input 'y
' add "$SRC_DIR/a"

  assert_rc 0 "$HM_STATUS" "add succeeds"
  assert_sql "4" "SELECT COUNT(*) FROM paths;" "every nested directory was registered"
}

test_add_deduplicates_overlapping_arguments() {
  _test_setup add_overlap
  mkdir -p "$SRC_DIR/sub"
  printf 'a\n' > "$SRC_DIR/sub/a.txt"

  run_hm_input 'y
' add "$SRC_DIR" "$SRC_DIR/sub" "$SRC_DIR/sub/a.txt"

  assert_rc 0 "$HM_STATUS" "add succeeds"
  assert_sql "3" "SELECT COUNT(*) FROM paths;" "the overlapping paths were registered once"
  assert_sql "3" "SELECT COUNT(*) FROM pending_paths;" "the pending set has no duplicates"
}

test_add_reports_an_existing_path() {
  _test_setup add_existing
  printf 'a\n' > "$SRC_DIR/a.txt"

  run_hm_input 'y
' add "$SRC_DIR/a.txt"
  assert_rc 0 "$HM_STATUS" "the first add succeeds"

  run_hm_input 'y
' add "$SRC_DIR/a.txt"

  assert_rc 0 "$HM_STATUS" "the second add succeeds"
  assert_contains "$HM_OUTPUT" "PENDING" "the existing path is reported as pending"
  assert_contains "$HM_OUTPUT" "1 paths already pending" "the count comes from the database"
  assert_sql "1" "SELECT COUNT(*) FROM paths;" "the path was not inserted twice"
}

test_add_handles_special_file_names() {
  _test_setup add_special
  printf 'a\n' > "$SRC_DIR/with space.txt"
  printf 'b\n' > "$SRC_DIR/with'quote.txt"
  printf 'c\n' > "$SRC_DIR/with
newline.txt"
  printf 'd\n' > "$SRC_DIR/with\"double.txt"

  run_hm_input 'y
' add "$SRC_DIR"

  assert_rc 0 "$HM_STATUS" "add succeeds with special file names"
  assert_sql "5" "SELECT COUNT(*) FROM paths;" \
    "the directory and all four files were registered"
  assert_sql "1" "SELECT COUNT(*) FROM paths WHERE path LIKE '%newline%';" \
    "the path with a newline was registered"
}

test_add_rejects_a_missing_path() {
  _test_setup add_missing

  run_hm_input 'y
' add "$SRC_DIR/does-not-exist.txt"

  assert_rc 3 "$HM_STATUS" "add fails for a missing path"
  assert_contains "$HM_OUTPUT" "Path not found" "the error explains the problem"
  assert_sql "0" "SELECT COUNT(*) FROM paths;" "nothing was registered"
}

test_add_rejects_a_symbolic_link_argument() {
  _test_setup add_symlink_arg
  printf 'a\n' > "$SRC_DIR/a.txt"
  ln -s "$SRC_DIR/a.txt" "$SRC_DIR/link.txt"

  run_hm_input 'y
' add "$SRC_DIR/link.txt"

  assert_rc 3 "$HM_STATUS" "add fails for a symbolic link argument"
  assert_contains "$HM_OUTPUT" "Symbolic links are not supported" "the error explains the policy"
}

test_add_skips_symbolic_links_inside_a_directory() {
  _test_setup add_symlink_inner
  printf 'a\n' > "$SRC_DIR/a.txt"
  ln -s /etc/passwd "$SRC_DIR/link.txt"

  run_hm_input 'y
' add "$SRC_DIR"

  assert_rc 0 "$HM_STATUS" "add succeeds"
  assert_contains "$HM_OUTPUT" "Skipping symbolic link" "the skipped link is reported"
  assert_sql "2" "SELECT COUNT(*) FROM paths;" "only the directory and the regular file were registered"
}

test_add_does_not_touch_the_content_store() {
  _test_setup add_no_store
  printf 'a\n' > "$SRC_DIR/a.txt"

  run_hm_input 'y
' add "$SRC_DIR"

  assert_rc 0 "$HM_STATUS" "add succeeds"
  assert_count "0" "$(find "$HM_DIR/store" -type f | wc -l)" \
    "add did not create a content object"
  assert_sql "0" "SELECT COUNT(*) FROM files;" "add did not register a content object"
  assert_sql "0" "SELECT COUNT(*) FROM generations;" "add did not create a generation"
}

test_add_does_not_create_a_generation() {
  _test_setup add_no_gen
  printf 'a\n' > "$SRC_DIR/a.txt"

  run_hm_input 'y
' add "$SRC_DIR/a.txt"

  assert_sql "0" "SELECT COUNT(*) FROM generations;" "no generation was created"
  assert_sql "0" "SELECT COUNT(*) FROM generation_entries;" "no generation entry was created"
}

test_add_does_not_modify_the_source_files() {
  _test_setup add_no_modify
  printf 'original\n' > "$SRC_DIR/a.txt"
  local before after mode_before mode_after

  before="$(stat -c '%s %Y %a' -- "$SRC_DIR/a.txt")"

  run_hm_input 'y
' add "$SRC_DIR/a.txt"

  after="$(stat -c '%s %Y %a' -- "$SRC_DIR/a.txt")"
  mode_before="$(stat -c '%a' -- "$SRC_DIR/a.txt")"
  mode_after="$(stat -c '%a' -- "$SRC_DIR/a.txt")"

  assert_eq "$before" "$after" "the source file was not modified"
  assert_eq "$mode_before" "$mode_after" "the permissions of the source file were not modified"
  assert_file_content "$SRC_DIR/a.txt" "original" "the content of the source file is unchanged"
}

test_add_declining_changes_nothing() {
  _test_setup add_decline
  printf 'a\n' > "$SRC_DIR/a.txt"

  run_hm_input 'n
' add "$SRC_DIR/a.txt"

  assert_rc 0 "$HM_STATUS" "declining is not an error"
  assert_contains "$HM_OUTPUT" "Cancelled" "the cancellation is reported"
  assert_sql "0" "SELECT COUNT(*) FROM paths;" "no path was registered"
  assert_sql "0" "SELECT COUNT(*) FROM pending_paths;" "the pending set is unchanged"
}

test_add_requires_an_argument() {
  _test_setup add_no_arg

  run_hm add

  assert_rc 2 "$HM_STATUS" "add without an argument is a usage error"
}

test_add_refresh_prunes_vanished_paths() {
  _test_setup add_refresh
  mkdir -p "$SRC_DIR/sub"
  printf 'a\n' > "$SRC_DIR/a.txt"
  printf 'b\n' > "$SRC_DIR/sub/b.txt"

  run_hm_input 'y
' add "$SRC_DIR"
  assert_rc 0 "$HM_STATUS" "the first add succeeds"
  assert_sql "4" "SELECT COUNT(*) FROM pending_paths;" "four paths are pending"

  rm -f -- "$SRC_DIR/sub/b.txt"

  run_hm_input 'y
' add "$SRC_DIR"

  assert_rc 0 "$HM_STATUS" "the refresh succeeds"
  assert_contains "$HM_OUTPUT" "REMOVED" "the vanished path is reported"
  assert_sql "3" "SELECT COUNT(*) FROM pending_paths;" "the vanished path left the pending set"
  assert_sql "1" "SELECT COUNT(*) FROM paths WHERE path = '$SRC_DIR/sub/b.txt';" \
    "the vanished path is still in the registry"
}
