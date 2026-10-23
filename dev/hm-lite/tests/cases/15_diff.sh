#!/usr/bin/env bash
#
# tests/cases/15_diff.sh - the diff command.
#
# The test list is read by the runner, shellcheck only sees this
# file and therefore reports the variable as unused.
# shellcheck disable=SC2034

TESTS=(
  test_diff_reports_the_added_removed_and_changed_paths
  test_diff_reports_a_content_change
  test_diff_reports_a_mode_change
  test_diff_reports_a_type_change
  test_diff_hides_the_unchanged_paths_by_default
  test_diff_shows_the_unchanged_paths_with_all
  test_diff_reports_no_differences
  test_diff_compares_several_generations_in_order
  test_diff_compares_in_the_given_order
  test_diff_rejects_a_single_generation
  test_diff_rejects_no_generations
  test_diff_rejects_duplicate_generations
  test_diff_rejects_an_unknown_generation
  test_diff_rejects_unknown_options
  test_diff_requires_an_initialized_project
  test_diff_does_not_change_the_project
  test_diff_fails_when_a_query_fails
  test_diff_colours_the_markers
  test_diff_has_no_colour_in_a_pipe
)

# _diff_fixture - three generations.
#
# Generation 1: a.txt, b.txt "b\n", d.txt
# Generation 2: a.txt unchanged, b.txt changed, c.txt added, d.txt gone
# Generation 3: only the mode of a.txt changed, from 644 to 600
_diff_fixture() {
  _test_setup diff_fixture
  printf 'a\n' > "$SRC_DIR/a.txt"
  printf 'b\n' > "$SRC_DIR/b.txt"
  printf 'd\n' > "$SRC_DIR/d.txt"

  run_hm_input 'y\n' add "$SRC_DIR"
  run_hm_input 'y\n' gen --name "first"

  printf 'b2\n' > "$SRC_DIR/b.txt"
  printf 'c\n' > "$SRC_DIR/c.txt"
  rm -f -- "$SRC_DIR/d.txt"

  run_hm_input 'y\n' add "$SRC_DIR"
  run_hm_input 'y\n' gen --name "second"

  chmod 600 -- "$SRC_DIR/a.txt"
  run_hm_input 'y\n' add "$SRC_DIR/a.txt"
  run_hm_input 'y\n' gen --name "third"
}

# _diff_run_colour MODE ARGUMENTS... - run diff with an explicit colour
# mode, keeping only standard output.
_diff_run_colour() {
  local mode="$1"
  shift
  local out status

  out="$(env -u NO_COLOR HM_COLOR="$mode" "$HM_BIN" "$@" 2>/dev/null </dev/null)"
  status=$?

  HM_OUTPUT="$out"
  HM_STATUS="$status"
  return 0
}

test_diff_reports_the_added_removed_and_changed_paths() {
  _diff_fixture

  run_hm diff 1 2

  assert_rc 0 "$HM_STATUS" "diff succeeds even when the generations differ"
  assert_contains "$HM_OUTPUT" "+ $SRC_DIR/c.txt" "the added path is marked"
  assert_contains "$HM_OUTPUT" "- $SRC_DIR/d.txt" "the removed path is marked"
  assert_contains "$HM_OUTPUT" "~ $SRC_DIR/b.txt" "the changed path is marked"
  assert_not_contains "$HM_OUTPUT" "+ $SRC_DIR/a.txt" "an unchanged path is not added"
}

test_diff_reports_a_content_change() {
  _diff_fixture

  run_hm diff 1 2

  assert_rc 0 "$HM_STATUS" "diff succeeds"
  assert_contains "$HM_OUTPUT" "~ $SRC_DIR/b.txt (content)" "the content change is named"
}

test_diff_reports_a_mode_change() {
  _diff_fixture

  run_hm diff 2 3

  assert_rc 0 "$HM_STATUS" "diff succeeds"
  assert_contains "$HM_OUTPUT" "~ $SRC_DIR/a.txt (mode 644 -> 600)" "the mode change is named"
}

test_diff_reports_a_type_change() {
  _test_setup diff_type
  printf 'x\n' > "$SRC_DIR/x"
  run_hm_input 'y\n' add "$SRC_DIR/x"
  run_hm_input 'y\n' gen

  rm -f -- "$SRC_DIR/x"
  mkdir -p -- "$SRC_DIR/x"
  run_hm_input 'y\n' add "$SRC_DIR/x"
  run_hm_input 'y\n' gen

  run_hm diff 1 2

  assert_rc 0 "$HM_STATUS" "diff succeeds"
  assert_contains "$HM_OUTPUT" "~ $SRC_DIR/x (type file -> dir" "the type change is named"
}

test_diff_hides_the_unchanged_paths_by_default() {
  _diff_fixture

  run_hm diff 1 2

  assert_rc 0 "$HM_STATUS" "diff succeeds"
  assert_not_contains "$HM_OUTPUT" "= $SRC_DIR/a.txt" "an unchanged path is hidden"
  assert_contains "$HM_OUTPUT" "1 added, 1 removed, 1 changed, 2 unchanged" \
    "the summary counts every path"
}

test_diff_shows_the_unchanged_paths_with_all() {
  _diff_fixture

  run_hm diff 1 2 --all

  assert_rc 0 "$HM_STATUS" "diff succeeds"
  assert_contains "$HM_OUTPUT" "= $SRC_DIR/a.txt" "the unchanged path is shown"
}

test_diff_reports_no_differences() {
  _test_setup diff_same
  printf 'a\n' > "$SRC_DIR/a.txt"
  run_hm_input 'y\n' add "$SRC_DIR/a.txt"
  run_hm_input 'y\n' gen
  run_hm_input 'y\n' add "$SRC_DIR/a.txt"
  run_hm_input 'y\n' gen

  run_hm diff 1 2

  assert_rc 0 "$HM_STATUS" "diff succeeds"
  assert_contains "$HM_OUTPUT" "No differences." "the equal generations are reported"
  assert_contains "$HM_OUTPUT" "0 added, 0 removed, 0 changed, 1 unchanged" \
    "the summary reports the unchanged entry"
}

test_diff_compares_several_generations_in_order() {
  _diff_fixture

  run_hm diff 1 2 3

  assert_rc 0 "$HM_STATUS" "diff succeeds"
  assert_contains "$HM_OUTPUT" "Generation 1 -> 2" "the first pair is compared"
  assert_contains "$HM_OUTPUT" "Generation 2 -> 3" "the second pair is compared"
  assert_not_contains "$HM_OUTPUT" "Generation 3 -> 1" "the pairs follow the given order"
  assert_contains "$HM_OUTPUT" "+ $SRC_DIR/c.txt" "the first pair reports its change"
  assert_contains "$HM_OUTPUT" "~ $SRC_DIR/a.txt (mode 644 -> 600)" "the second pair reports its change"
}

test_diff_compares_in_the_given_order() {
  _diff_fixture

  run_hm diff 2 1

  assert_rc 0 "$HM_STATUS" "diff succeeds"
  assert_contains "$HM_OUTPUT" "Generation 2 -> 1" "the pair follows the given order"
  assert_contains "$HM_OUTPUT" "+ $SRC_DIR/d.txt" "a path that came back is added"
  assert_contains "$HM_OUTPUT" "- $SRC_DIR/c.txt" "a path that went away is removed"
}

test_diff_rejects_a_single_generation() {
  _diff_fixture

  run_hm diff 1

  assert_rc 2 "$HM_STATUS" "a single generation is a usage error"
  assert_contains "$HM_OUTPUT" "two generations" "the error explains the problem"
}

test_diff_rejects_no_generations() {
  _diff_fixture

  run_hm diff

  assert_rc 2 "$HM_STATUS" "no generation is a usage error"
  assert_contains "$HM_OUTPUT" "Usage: hm diff" "the usage is printed"
}

test_diff_rejects_duplicate_generations() {
  _diff_fixture

  run_hm diff 1 1

  assert_rc 2 "$HM_STATUS" "the same generation twice is a usage error"
  assert_contains "$HM_OUTPUT" "distinct" "the error explains the problem"
}

test_diff_rejects_an_unknown_generation() {
  _diff_fixture

  run_hm diff 1 99

  assert_rc 4 "$HM_STATUS" "an unknown generation is a state error"
  assert_contains "$HM_OUTPUT" "no generation" "the error explains the problem"
}

test_diff_rejects_unknown_options() {
  _diff_fixture

  run_hm diff 1 2 --bogus

  assert_rc 2 "$HM_STATUS" "an unknown option is a usage error"
  assert_contains "$HM_OUTPUT" "Unknown option" "the error explains the problem"
}

test_diff_requires_an_initialized_project() {
  _test_setup diff_uninitialized raw

  run_hm diff 1 2

  assert_rc 3 "$HM_STATUS" "diff fails on an uninitialized project"
  assert_contains "$HM_OUTPUT" "not initialized" "the error explains the problem"
}

test_diff_does_not_change_the_project() {
  _diff_fixture

  local before after

  before="$(sqlite3 "$HM_DIR/db.sqlite" "
    SELECT (SELECT COUNT(*) FROM generations) || ':' ||
           (SELECT COUNT(*) FROM generation_entries) || ':' ||
           (SELECT COUNT(*) FROM files) || ':' ||
           (SELECT COUNT(*) FROM paths) || ':' ||
           (SELECT COUNT(*) FROM pending_paths) || ':' ||
           COALESCE((SELECT value FROM state WHERE key = 'selected_generation'), '');")"

  run_hm diff 1 2 3
  assert_rc 0 "$HM_STATUS" "diff succeeds"

  after="$(sqlite3 "$HM_DIR/db.sqlite" "
    SELECT (SELECT COUNT(*) FROM generations) || ':' ||
           (SELECT COUNT(*) FROM generation_entries) || ':' ||
           (SELECT COUNT(*) FROM files) || ':' ||
           (SELECT COUNT(*) FROM paths) || ':' ||
           (SELECT COUNT(*) FROM pending_paths) || ':' ||
           COALESCE((SELECT value FROM state WHERE key = 'selected_generation'), '');")"

  assert_eq "$before" "$after" "the database is unchanged"
}

test_diff_fails_when_a_query_fails() {
  _diff_fixture

  sqlite3 "$HM_DIR/db.sqlite" 'ALTER TABLE files RENAME TO files_gone;'

  run_hm diff 1 2

  assert_rc 5 "$HM_STATUS" "a failing query stops the command"
  assert_contains "$HM_OUTPUT" "Cannot read the generation" "the reason is named"
}

test_diff_colours_the_markers() {
  _diff_fixture

  _diff_run_colour always diff 1 2

  assert_rc 0 "$HM_STATUS" "diff succeeds"
  assert_contains "$HM_OUTPUT" $'\033[1;96m' "the heading is bold and bright cyan"
  assert_contains "$HM_OUTPUT" $'\033[92m' "the added path is bright green"
  assert_contains "$HM_OUTPUT" $'\033[91m' "the removed path is bright red"
  assert_contains "$HM_OUTPUT" $'\033[93m' "the changed path is bright yellow"
  assert_contains "$HM_OUTPUT" $'\033[0m' "the colour is reset"
}

test_diff_has_no_colour_in_a_pipe() {
  _diff_fixture

  _diff_run_colour auto diff 1 2

  assert_rc 0 "$HM_STATUS" "diff succeeds"
  assert_not_contains "$HM_OUTPUT" $'\033[' "no escape sequence is written to a pipe"
}
