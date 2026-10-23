#!/usr/bin/env bash
#
# tests/cases/13_status.sh - status behaviour.
#
# The test list is read by the runner, shellcheck only sees this
# file and therefore reports the variable as unused.
# shellcheck disable=SC2034

TESTS=(
  test_status_prints_the_project_overview
  test_status_reports_the_store_space
  test_status_reports_every_generation_with_its_size
  test_status_counts_shared_content_once_per_generation
  test_status_marks_the_selected_generation
  test_status_shows_the_comment_of_a_generation
  test_status_reports_unreferenced_objects
  test_status_reports_missing_objects
  test_status_works_without_generations
  test_status_rejects_unknown_options
  test_status_rejects_an_argument
  test_status_requires_an_initialized_project
  test_status_does_not_change_the_project
  test_status_fails_when_a_query_fails
  test_status_colours_the_headings
  test_status_has_no_colour_in_a_pipe
)

# _status_fixture - three generations.
#
#   a.txt  "a\n"    (2 bytes)
#   b.txt  "a\n"    (2 bytes, the same content as a.txt)
#   c.txt  "ccc\n"  (4 bytes)
#
# Generation 1: a.txt                  -> 1 entry,  1 object, 2 bytes
# Generation 2: a.txt + b.txt          -> 2 entries, 1 object, 2 bytes
# Generation 3: a.txt + b.txt + c.txt  -> 3 entries, 2 objects, 6 bytes
#
# The store holds two objects and six bytes.
_status_fixture() {
  _test_setup status_fixture
  printf 'a\n' > "$SRC_DIR/a.txt"
  printf 'a\n' > "$SRC_DIR/b.txt"
  printf 'ccc\n' > "$SRC_DIR/c.txt"

  run_hm_input 'y\n' add "$SRC_DIR/a.txt"
  run_hm_input 'y\n' gen --name "first"

  run_hm_input 'y\n' add "$SRC_DIR/b.txt"
  run_hm_input 'y\n' gen --name "second"

  run_hm_input 'y\n' add "$SRC_DIR/c.txt"
  run_hm_input 'y\n' gen --name "third"
}

# _status_line NAME - print the status table line of the generation NAME.
_status_line() {
  printf '%s\n' "$HM_OUTPUT" | grep -F " $1"
}

# _status_run_colour MODE - run status with an explicit colour mode.
_status_run_colour() {
  local mode="$1"
  local out status

  out="$(env -u NO_COLOR HM_COLOR="$mode" "$HM_BIN" status 2>&1 </dev/null)"
  status=$?

  HM_OUTPUT="$out"
  HM_STATUS="$status"
  return 0
}

test_status_prints_the_project_overview() {
  _status_fixture

  run_hm status

  assert_rc 0 "$HM_STATUS" "status succeeds"
  assert_contains "$HM_OUTPUT" "HM-Lite status" "the command names itself"
  assert_contains "$HM_OUTPUT" "Project:" "the project directory is printed"
  assert_contains "$HM_OUTPUT" "Generations:" "the number of generations is printed"
  assert_contains "$HM_OUTPUT" "Selected:" "the selected generation is printed"
  assert_contains "$HM_OUTPUT" "Tracked paths:" "the number of tracked paths is printed"
  assert_contains "$HM_OUTPUT" "Pending paths:" "the number of pending paths is printed"
}

test_status_reports_the_store_space() {
  _status_fixture

  run_hm status

  assert_rc 0 "$HM_STATUS" "status succeeds"
  assert_contains "$HM_OUTPUT" "Store" "the store section is printed"
  assert_contains "$HM_OUTPUT" "Location:" "the store location is printed"
  assert_contains "$HM_OUTPUT" "Objects:" "the object count is printed"
  assert_contains "$HM_OUTPUT" "Size:" "the store size is printed"
  assert_contains "$HM_OUTPUT" "6 B (6 bytes)" "the size of the store is correct"
  assert_contains "$HM_OUTPUT" "Referenced:" "the referenced objects are printed"
  assert_contains "$HM_OUTPUT" "Unreferenced:" "the unreferenced objects are printed"
  assert_contains "$HM_OUTPUT" "Missing:" "the missing objects are printed"
}

test_status_reports_every_generation_with_its_size() {
  _status_fixture

  run_hm status

  assert_rc 0 "$HM_STATUS" "status succeeds"
  assert_contains "$HM_OUTPUT" "SIZE" "the table has a size column"
  assert_contains "$(_status_line first)" "2 B" "the size of the first generation is printed"
  assert_contains "$(_status_line second)" "2 B" "the size of the second generation is printed"
  assert_contains "$(_status_line third)" "6 B" "the size of the third generation is printed"
}

test_status_counts_shared_content_once_per_generation() {
  _status_fixture

  run_hm status

  local line
  line="$(_status_line second)"

  assert_contains "$line" " second" "the second generation is listed"
  assert_contains "$line" " 2 " "the shared content is one entry"
  assert_contains "$line" "2 B" "the shared content is counted once, not per entry"
}

test_status_marks_the_selected_generation() {
  _status_fixture

  run_hm switch 2
  assert_rc 0 "$HM_STATUS" "the fixture selects the second generation"

  run_hm status

  assert_rc 0 "$HM_STATUS" "status succeeds"
  assert_contains "$HM_OUTPUT" "Selected:" "the selection is printed"
  assert_contains "$(_status_line second)" "*" "the selected generation is marked"
  assert_not_contains "$(_status_line first)" "*" "the other generation is not marked"
}

test_status_shows_the_comment_of_a_generation() {
  _test_setup status_comment
  printf 'a\n' > "$SRC_DIR/a.txt"

  run_hm_input 'y\n' add "$SRC_DIR/a.txt"
  run_hm_input 'y\n' gen --name "commented" --comment "before the upgrade"

  run_hm status

  assert_rc 0 "$HM_STATUS" "status succeeds"
  assert_contains "$HM_OUTPUT" "COMMENT" "the comment column is printed"
  assert_contains "$HM_OUTPUT" "before the upgrade" "the comment is printed"
}

test_status_reports_unreferenced_objects() {
  _status_fixture

  run_hm delete 3 --yes
  assert_rc 0 "$HM_STATUS" "the fixture deletes the third generation"

  run_hm status

  assert_rc 0 "$HM_STATUS" "status succeeds"
  assert_contains "$HM_OUTPUT" "Unreferenced:" "the unreferenced objects are printed"
  assert_contains "$HM_OUTPUT" "4 B (4 bytes)" "the size of the unreferenced object is printed"
  assert_contains "$HM_OUTPUT" "hm clean" "the command that reclaims the space is named"
}

test_status_reports_missing_objects() {
  _status_fixture

  local hash
  hash="$(sqlite3 "$HM_DIR/db.sqlite" "
    SELECT f.hash
      FROM files f
      JOIN generation_entries ge ON ge.file_id = f.id
      JOIN paths p ON p.id = ge.path_id
     WHERE p.path = '$SRC_DIR/a.txt'
     LIMIT 1;")"
  [[ -n "$hash" ]] || { _test_fail "the fixture has no content object for a.txt"; return 0; }

  rm -f "$STORE_DIR/${hash:0:2}/$hash"

  run_hm status

  assert_rc 0 "$HM_STATUS" "a damaged store is reported, not fatal"
  assert_contains "$HM_OUTPUT" "Missing:" "the missing objects are printed"
  assert_contains "$HM_OUTPUT" "2 B (2 bytes)" "the size of the missing object is printed"
  assert_contains "$HM_OUTPUT" "WARNING" "the damage is logged"
}

test_status_works_without_generations() {
  _test_setup status_empty

  run_hm status

  assert_rc 0 "$HM_STATUS" "status works on an empty project"
  assert_contains "$HM_OUTPUT" "Generations:" "the overview is printed"
  assert_contains "$HM_OUTPUT" "No generations yet." "the empty history is stated"
  assert_contains "$HM_OUTPUT" "0 B (0 bytes)" "the empty store is reported"
}

test_status_rejects_unknown_options() {
  _status_fixture

  run_hm status --bogus

  assert_rc 2 "$HM_STATUS" "an unknown option is a usage error"
  assert_contains "$HM_OUTPUT" "Unknown option" "the error explains the problem"
}

test_status_rejects_an_argument() {
  _status_fixture

  run_hm status 1

  assert_rc 2 "$HM_STATUS" "status does not take an argument"
  assert_contains "$HM_OUTPUT" "Usage: hm status" "the usage is printed"
}

test_status_requires_an_initialized_project() {
  _test_setup status_uninit raw

  run_hm status

  assert_rc 3 "$HM_STATUS" "status fails on an uninitialized project"
  assert_contains "$HM_OUTPUT" "not initialized" "the error explains the problem"
}

test_status_does_not_change_the_project() {
  _status_fixture

  local before after

  before="$(sqlite3 "$HM_DIR/db.sqlite" "
    SELECT (SELECT COUNT(*) FROM generations) || ':' ||
           (SELECT COUNT(*) FROM generation_entries) || ':' ||
           (SELECT COUNT(*) FROM files) || ':' ||
           (SELECT COUNT(*) FROM paths) || ':' ||
           (SELECT COUNT(*) FROM pending_paths) || ':' ||
           COALESCE((SELECT value FROM state WHERE key = 'selected_generation'), '');")"

  run_hm status
  assert_rc 0 "$HM_STATUS" "status succeeds"

  after="$(sqlite3 "$HM_DIR/db.sqlite" "
    SELECT (SELECT COUNT(*) FROM generations) || ':' ||
           (SELECT COUNT(*) FROM generation_entries) || ':' ||
           (SELECT COUNT(*) FROM files) || ':' ||
           (SELECT COUNT(*) FROM paths) || ':' ||
           (SELECT COUNT(*) FROM pending_paths) || ':' ||
           COALESCE((SELECT value FROM state WHERE key = 'selected_generation'), '');")"

  assert_eq "$before" "$after" "the database is unchanged"
  assert_sql "2" "SELECT COUNT(*) FROM files;" "the content objects are unchanged"
  assert_sql "3" "SELECT COUNT(*) FROM generations;" "the generations are unchanged"
}

test_status_fails_when_a_query_fails() {
  _status_fixture

  sqlite3 "$HM_DIR/db.sqlite" 'ALTER TABLE files RENAME TO files_gone;'

  run_hm status

  assert_rc 5 "$HM_STATUS" "a failing query stops the command"
  assert_contains "$HM_OUTPUT" "Cannot read the content objects" "the reason is named"
}

test_status_colours_the_headings() {
  _status_fixture

  _status_run_colour always

  assert_rc 0 "$HM_STATUS" "status succeeds"
  assert_contains "$HM_OUTPUT" $'\033[1;96m' "the headings are bold and bright cyan"
  assert_contains "$HM_OUTPUT" $'\033[2m' "the labels are dim"
  assert_contains "$HM_OUTPUT" $'\033[0m' "the colour is reset"
}

test_status_has_no_colour_in_a_pipe() {
  _status_fixture

  _status_run_colour auto

  assert_rc 0 "$HM_STATUS" "status succeeds"
  assert_not_contains "$HM_OUTPUT" $'\033[' "no escape sequence is written to a pipe"
}
