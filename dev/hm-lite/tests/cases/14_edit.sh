#!/usr/bin/env bash
#
# tests/cases/14_edit.sh - the edit command.
#
# The test list is read by the runner, shellcheck only sees this
# file and therefore reports the variable as unused.
# shellcheck disable=SC2034

TESTS=(
  test_edit_sets_the_name_of_a_generation
  test_edit_sets_the_comment_of_a_generation
  test_edit_sets_the_name_and_the_comment
  test_edit_replaces_an_existing_name_and_comment
  test_edit_clears_the_name
  test_edit_clears_the_comment
  test_edit_is_visible_in_show
  test_edit_preserves_the_entries_and_the_selection
  test_edit_asks_for_a_confirmation
  test_edit_accepts_the_confirmation
  test_edit_requires_a_metadata_option
  test_edit_rejects_conflicting_options
  test_edit_rejects_an_empty_value
  test_edit_requires_exactly_one_generation
  test_edit_rejects_an_unknown_generation
  test_edit_rejects_unknown_options
  test_edit_requires_an_initialized_project
  test_edit_fails_when_the_update_fails
  test_edit_colours_the_preview
  test_edit_has_no_colour_in_a_pipe
)

# _edit_fixture - one generation with one tracked file.
_edit_fixture() {
  _test_setup edit_fixture
  printf 'a\n' > "$SRC_DIR/a.txt"
  run_hm_input 'y\n' add "$SRC_DIR/a.txt"
  run_hm_input 'y\n' gen
}

# _edit_run_colour MODE ARGUMENTS... - run edit with an explicit colour mode,
# keeping only standard output.
_edit_run_colour() {
  local mode="$1"
  shift
  local out status

  out="$(env -u NO_COLOR HM_COLOR="$mode" "$HM_BIN" "$@" 2>/dev/null </dev/null)"
  status=$?

  HM_OUTPUT="$out"
  HM_STATUS="$status"
  return 0
}

test_edit_sets_the_name_of_a_generation() {
  _edit_fixture

  run_hm edit 1 --name "first name" --yes

  assert_rc 0 "$HM_STATUS" "edit succeeds"
  assert_sql "first name" "SELECT name FROM generations WHERE id = 1;" "the name is stored"
  assert_contains "$HM_OUTPUT" "Edit preview" "the change is previewed"
  assert_contains "$HM_OUTPUT" "first name" "the new name is previewed"
}

test_edit_sets_the_comment_of_a_generation() {
  _edit_fixture

  run_hm edit 1 --comment "a note" --yes

  assert_rc 0 "$HM_STATUS" "edit succeeds"
  assert_sql "a note" "SELECT comment FROM generations WHERE id = 1;" "the comment is stored"
}

test_edit_sets_the_name_and_the_comment() {
  _edit_fixture

  run_hm edit 1 --name "first name" --comment "a note" --yes

  assert_rc 0 "$HM_STATUS" "edit succeeds"
  assert_sql "first name" "SELECT name FROM generations WHERE id = 1;" "the name is stored"
  assert_sql "a note" "SELECT comment FROM generations WHERE id = 1;" "the comment is stored"
}

test_edit_replaces_an_existing_name_and_comment() {
  _test_setup edit_replace
  printf 'a\n' > "$SRC_DIR/a.txt"
  run_hm_input 'y\n' add "$SRC_DIR/a.txt"
  run_hm_input 'y\n' gen --name "old name" --comment "old note"

  run_hm edit 1 --name "new name" --comment "new note" --yes

  assert_rc 0 "$HM_STATUS" "edit succeeds"
  assert_sql "new name" "SELECT name FROM generations WHERE id = 1;" "the name is replaced"
  assert_sql "new note" "SELECT comment FROM generations WHERE id = 1;" "the comment is replaced"
}

test_edit_clears_the_name() {
  _test_setup edit_clear_name
  printf 'a\n' > "$SRC_DIR/a.txt"
  run_hm_input 'y\n' add "$SRC_DIR/a.txt"
  run_hm_input 'y\n' gen --name "old name"

  run_hm edit 1 --clear-name --yes

  assert_rc 0 "$HM_STATUS" "edit succeeds"
  assert_sql "1" "SELECT name IS NULL FROM generations WHERE id = 1;" "the name is cleared"
}

test_edit_clears_the_comment() {
  _test_setup edit_clear_comment
  printf 'a\n' > "$SRC_DIR/a.txt"
  run_hm_input 'y\n' add "$SRC_DIR/a.txt"
  run_hm_input 'y\n' gen --comment "old note"

  run_hm edit 1 --clear-comment --yes

  assert_rc 0 "$HM_STATUS" "edit succeeds"
  assert_sql "1" "SELECT comment IS NULL FROM generations WHERE id = 1;" "the comment is cleared"
}

test_edit_is_visible_in_show() {
  _edit_fixture

  run_hm edit 1 --name "visible name" --comment "visible note" --yes
  assert_rc 0 "$HM_STATUS" "edit succeeds"

  run_hm show 1

  assert_rc 0 "$HM_STATUS" "show succeeds"
  assert_contains "$HM_OUTPUT" "visible name" "show prints the new name"
  assert_contains "$HM_OUTPUT" "visible note" "show prints the new comment"
}

test_edit_preserves_the_entries_and_the_selection() {
  _edit_fixture
  run_hm switch 1
  assert_rc 0 "$HM_STATUS" "the fixture selects the generation"

  run_hm edit 1 --name "selected" --yes

  assert_rc 0 "$HM_STATUS" "edit succeeds"
  assert_sql "1" "SELECT COUNT(*) FROM generation_entries WHERE generation_id = 1;" "the entries are unchanged"
  assert_sql "1" "SELECT value FROM state WHERE key = 'selected_generation';" "the selection is unchanged"
}

test_edit_asks_for_a_confirmation() {
  _edit_fixture

  run_hm_input 'n\n' edit 1 --name "not stored"

  assert_rc 7 "$HM_STATUS" "a declined edit is not an error"
  assert_sql "" "SELECT COALESCE(name, '') FROM generations WHERE id = 1;" "the name is unchanged"
}

test_edit_accepts_the_confirmation() {
  _edit_fixture

  run_hm_input 'y\n' edit 1 --name "stored"

  assert_rc 0 "$HM_STATUS" "a confirmed edit succeeds"
  assert_sql "stored" "SELECT name FROM generations WHERE id = 1;" "the name is stored"
}

test_edit_requires_a_metadata_option() {
  _edit_fixture

  run_hm edit 1 --yes

  assert_rc 2 "$HM_STATUS" "edit without a metadata option is a usage error"
  assert_contains "$HM_OUTPUT" "At least one of" "the error explains the problem"
}

test_edit_rejects_conflicting_options() {
  _edit_fixture

  run_hm edit 1 --name "new" --clear-name --yes
  assert_rc 2 "$HM_STATUS" "a name and --clear-name conflict"

  run_hm edit 1 --comment "new" --clear-comment --yes
  assert_rc 2 "$HM_STATUS" "a comment and --clear-comment conflict"
}

test_edit_rejects_an_empty_value() {
  _edit_fixture

  run_hm edit 1 --name "" --yes
  assert_rc 2 "$HM_STATUS" "an empty name is a usage error"

  run_hm edit 1 --comment "" --yes
  assert_rc 2 "$HM_STATUS" "an empty comment is a usage error"
}

test_edit_requires_exactly_one_generation() {
  _edit_fixture

  run_hm edit --name "new" --yes
  assert_rc 2 "$HM_STATUS" "a missing generation is a usage error"
  assert_contains "$HM_OUTPUT" "Usage: hm edit" "the usage is printed"

  run_hm edit 1 2 --name "new" --yes
  assert_rc 2 "$HM_STATUS" "a second generation is a usage error"
}

test_edit_rejects_an_unknown_generation() {
  _edit_fixture

  run_hm edit 99 --name "new" --yes

  assert_rc 4 "$HM_STATUS" "an unknown generation is a state error"
  assert_contains "$HM_OUTPUT" "no generation" "the error explains the problem"
}

test_edit_rejects_unknown_options() {
  _edit_fixture

  run_hm edit 1 --bogus --yes

  assert_rc 2 "$HM_STATUS" "an unknown option is a usage error"
  assert_contains "$HM_OUTPUT" "Unknown option" "the error explains the problem"
}

test_edit_requires_an_initialized_project() {
  _test_setup edit_uninitialized raw

  run_hm edit 1 --name "new" --yes

  assert_rc 3 "$HM_STATUS" "edit fails on an uninitialized project"
  assert_contains "$HM_OUTPUT" "not initialized" "the error explains the problem"
}

test_edit_fails_when_the_update_fails() {
  _edit_fixture

  sqlite3 "$HM_DIR/db.sqlite" 'ALTER TABLE generations RENAME TO generations_gone;'

  run_hm edit 1 --name "new" --yes

  assert_rc 5 "$HM_STATUS" "a failing query stops the command"
  assert_contains "$HM_OUTPUT" "Cannot read the generation" "the reason is named"
}

test_edit_colours_the_preview() {
  _edit_fixture

  _edit_run_colour always edit 1 --name "coloured" --yes

  assert_rc 0 "$HM_STATUS" "edit succeeds"
  assert_contains "$HM_OUTPUT" $'\033[1m' "the heading is bold"
  assert_contains "$HM_OUTPUT" $'\033[0m' "the colour is reset"
}

test_edit_has_no_colour_in_a_pipe() {
  _edit_fixture

  _edit_run_colour auto edit 1 --name "plain" --yes

  assert_rc 0 "$HM_STATUS" "edit succeeds"
  assert_not_contains "$HM_OUTPUT" $'\033[' "no escape sequence is written to a pipe"
}
