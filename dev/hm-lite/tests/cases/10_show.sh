#!/usr/bin/env bash
#
# tests/cases/10_show.sh - show behaviour.
#
# The test list is read by the runner, shellcheck only sees this
# file and therefore reports the variable as unused.
# shellcheck disable=SC2034

TESTS=(
  test_show_prints_the_generation_metadata
  test_show_prints_the_name_and_the_comment
  test_show_lists_the_entries
  test_show_marks_the_selected_generation
  test_show_reports_missing_objects
  test_show_rejects_an_unknown_generation
  test_show_requires_a_generation
  test_show_rejects_a_second_generation
  test_show_rejects_unknown_options
  test_show_does_not_change_the_project
  test_show_requires_an_initialized_project
  test_show_fails_when_a_query_fails
)

# _show_fixture - two generations, the second one carries both paths.
_show_fixture() {
  _test_setup show_fixture
  printf 'a\n' > "$SRC_DIR/a.txt"

  run_hm_input 'y\n' add "$SRC_DIR/a.txt"
  run_hm_input 'y\n' gen --name "first" --comment "the first generation"

  printf 'b\n' > "$SRC_DIR/b.txt"
  run_hm_input 'y\n' add "$SRC_DIR/b.txt"
  run_hm_input 'y\n' gen --name "second"
}

test_show_prints_the_generation_metadata() {
  _show_fixture

  run_hm show 2

  assert_rc 0 "$HM_STATUS" "show succeeds"
  assert_contains "$HM_OUTPUT" "Generation 2" "the generation is named"
  assert_contains "$HM_OUTPUT" "Created:" "the creation time is printed"
  assert_contains "$HM_OUTPUT" "Parent:" "the parent is printed"
  assert_contains "$HM_OUTPUT" "Entries:" "the entry count is printed"
  assert_contains "$HM_OUTPUT" "Objects:" "the object count is printed"
}

test_show_prints_the_name_and_the_comment() {
  _show_fixture

  run_hm show 1

  assert_rc 0 "$HM_STATUS" "show succeeds"
  assert_contains "$HM_OUTPUT" "Name:       first" "the name is printed"
  assert_contains "$HM_OUTPUT" "Comment:    the first generation" "the comment is printed"

  run_hm show 2

  assert_contains "$HM_OUTPUT" "Name:       second" "the name of the second generation is printed"
  assert_contains "$HM_OUTPUT" "Comment:    -" "a generation without a comment shows a dash"
}

test_show_lists_the_entries() {
  _show_fixture

  run_hm show 2

  assert_rc 0 "$HM_STATUS" "show succeeds"
  assert_contains "$HM_OUTPUT" "PATH" "the table header is printed"
  assert_contains "$HM_OUTPUT" "MODE" "the mode column is printed"
  assert_contains "$HM_OUTPUT" "$SRC_DIR/a.txt" "the carried forward path is printed"
  assert_contains "$HM_OUTPUT" "$SRC_DIR/b.txt" "the captured path is printed"

  run_hm show 1

  assert_contains "$HM_OUTPUT" "$SRC_DIR/a.txt" "the path of the first generation is printed"
  assert_not_contains "$HM_OUTPUT" "$SRC_DIR/b.txt" "the later path is not printed"
}

test_show_marks_the_selected_generation() {
  _show_fixture

  run_hm switch 2

  run_hm show 2
  assert_rc 0 "$HM_STATUS" "show succeeds"
  assert_contains "$HM_OUTPUT" "Selected:   yes" "the selected generation is marked"

  run_hm show 1
  assert_contains "$HM_OUTPUT" "Selected:   no" "the other generation is not marked"
}

test_show_reports_missing_objects() {
  _show_fixture

  local hash
  hash="$(sqlite3 "$HM_DIR/db.sqlite" "SELECT hash FROM files ORDER BY hash LIMIT 1;")"
  rm -f -- "$STORE_DIR/${hash:0:2}/$hash"

  run_hm show 2

  assert_rc 0 "$HM_STATUS" "show is read only and succeeds"
  assert_contains "$HM_OUTPUT" "Missing:    1 content object(s)" "the missing object is reported"
}

test_show_rejects_an_unknown_generation() {
  _show_fixture

  run_hm show 99

  assert_rc 4 "$HM_STATUS" "an unknown generation is a state error"
  assert_contains "$HM_OUTPUT" "no generation" "the error explains the problem"
}

test_show_requires_a_generation() {
  _show_fixture

  run_hm show

  assert_rc 2 "$HM_STATUS" "a missing generation is a usage error"
  assert_contains "$HM_OUTPUT" "Usage: hm show" "the usage is printed"
}

test_show_rejects_a_second_generation() {
  _show_fixture

  run_hm show 1 2

  assert_rc 2 "$HM_STATUS" "a second generation is a usage error"
  assert_contains "$HM_OUTPUT" "Usage: hm show" "the usage is printed"
}

test_show_rejects_unknown_options() {
  _show_fixture

  run_hm show --bogus 1

  assert_rc 2 "$HM_STATUS" "an unknown option is a usage error"
}

test_show_does_not_change_the_project() {
  _show_fixture
  local before after

  before="$(sqlite3 "$HM_DIR/db.sqlite" 'SELECT COUNT(*) FROM generations; SELECT COUNT(*) FROM generation_entries;')"

  run_hm show 1
  run_hm show 2

  after="$(sqlite3 "$HM_DIR/db.sqlite" 'SELECT COUNT(*) FROM generations; SELECT COUNT(*) FROM generation_entries;')"

  assert_eq "$before" "$after" "show did not change the database"
  assert_sql "2" "SELECT COUNT(*) FROM generations;" "no generation was created"
}

test_show_requires_an_initialized_project() {
  _test_setup show_uninit raw

  run_hm show 1

  assert_rc 3 "$HM_STATUS" "show fails on an uninitialized project"
  assert_contains "$HM_OUTPUT" "not initialized" "the error explains the problem"
}

test_show_fails_when_a_query_fails() {
  _show_fixture

  sqlite3 "$HM_DIR/db.sqlite" 'DROP TABLE generation_entries;'

  run_hm show 2

  assert_rc 5 "$HM_STATUS" "a failing query stops the command"
  assert_contains "$HM_OUTPUT" "Cannot read the generation 2" "the reason is named"
}
