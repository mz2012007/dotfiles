#!/usr/bin/env bash
#
# tests/cases/04_list.sh - list behaviour.
#
# The test list is read by the runner, shellcheck only sees this
# file and therefore reports the variable as unused.
# shellcheck disable=SC2034

TESTS=(
  test_list_shows_the_generations
  test_list_orders_the_generations_by_creation
  test_list_shows_a_single_generation
  test_list_shows_the_pending_paths
  test_list_shows_the_tracked_paths
  test_list_shows_the_store_statistics
  test_list_rejects_an_unknown_generation
  test_list_rejects_unknown_options
  test_list_does_not_change_the_project
  test_list_requires_an_initialized_project
  test_list_fails_when_a_query_fails
  test_list_fails_when_a_count_query_fails
)

# _list_fixture - create two generations with one path each.
_list_fixture() {
  _test_setup list_fixture
  printf 'a\n' > "$SRC_DIR/a.txt"

  run_hm_input 'y
' add "$SRC_DIR/a.txt"
  run_hm_input 'y
' gen

  printf 'b\n' > "$SRC_DIR/b.txt"
  run_hm_input 'y
' add "$SRC_DIR/b.txt"
  run_hm_input 'y
' gen
}

test_list_shows_the_generations() {
  _list_fixture

  run_hm list

  assert_rc 0 "$HM_STATUS" "list succeeds"
  assert_contains "$HM_OUTPUT" "ID" "the table header is printed"
  assert_contains "$HM_OUTPUT" "ENTRIES" "the entry count column is printed"
}

test_list_orders_the_generations_by_creation() {
  _list_fixture

  run_hm list

  assert_rc 0 "$HM_STATUS" "list succeeds"
  local first second
  first="$(printf '%s\n' "$HM_OUTPUT" | awk '/^[0-9]+[[:space:]]/ { print $1; exit }')"
  second="$(printf '%s\n' "$HM_OUTPUT" | awk '/^[0-9]+[[:space:]]/ { print $1 }' | sed -n '2p')"

  assert_eq "2" "$first" "the newest generation comes first"
  assert_eq "1" "$second" "the older generation comes second"
}

test_list_shows_a_single_generation() {
  _list_fixture

  run_hm list --generation 1

  assert_rc 0 "$HM_STATUS" "list succeeds"
  assert_contains "$HM_OUTPUT" "Generation 1" "the generation is named"
  assert_contains "$HM_OUTPUT" "$SRC_DIR/a.txt" "the entry of the generation is printed"
  assert_not_contains "$HM_OUTPUT" "$SRC_DIR/b.txt" "the other generation is not printed"
}

test_list_shows_the_pending_paths() {
  _test_setup list_pending
  printf 'a\n' > "$SRC_DIR/a.txt"

  run_hm_input 'y
' add "$SRC_DIR/a.txt"

  run_hm list --pending

  assert_rc 0 "$HM_STATUS" "list succeeds"
  assert_contains "$HM_OUTPUT" "$SRC_DIR/a.txt" "the pending path is printed"
  assert_contains "$HM_OUTPUT" "ADDED" "the table header is printed"
}

test_list_shows_the_tracked_paths() {
  _test_setup list_paths
  printf 'a\n' > "$SRC_DIR/a.txt"

  run_hm_input 'y
' add "$SRC_DIR/a.txt"

  run_hm list --paths

  assert_rc 0 "$HM_STATUS" "list succeeds"
  assert_contains "$HM_OUTPUT" "$SRC_DIR/a.txt" "the tracked path is printed"
  assert_contains "$HM_OUTPUT" "REGISTERED" "the table header is printed"
}

test_list_shows_the_store_statistics() {
  _list_fixture

  run_hm list --store

  assert_rc 0 "$HM_STATUS" "list succeeds"
  assert_contains "$HM_OUTPUT" "Objects in the store:" "the object count is printed"
  assert_contains "$HM_OUTPUT" "Unreferenced objects:" "the orphan count is printed"
  assert_contains "$HM_OUTPUT" "Generations:" "the generation count is printed"
}

test_list_rejects_an_unknown_generation() {
  _list_fixture

  run_hm list --generation 99

  assert_rc 4 "$HM_STATUS" "an unknown generation is a state error"
  assert_contains "$HM_OUTPUT" "no generation" "the error explains the problem"
}

test_list_rejects_unknown_options() {
  _test_setup list_options

  run_hm list --bogus

  assert_rc 2 "$HM_STATUS" "an unknown option is a usage error"
}

test_list_does_not_change_the_project() {
  _list_fixture
  local before after

  before="$(sqlite3 "$HM_DIR/db.sqlite" 'SELECT COUNT(*) FROM sqlite_master;')"

  run_hm list
  run_hm list --pending
  run_hm list --paths
  run_hm list --store
  run_hm list --generation 1

  after="$(sqlite3 "$HM_DIR/db.sqlite" 'SELECT COUNT(*) FROM sqlite_master;')"

  assert_eq "$before" "$after" "list did not change the database"
  assert_sql "2" "SELECT COUNT(*) FROM generations;" "no generation was created"
  assert_sql "0" "SELECT COUNT(*) FROM pending_paths;" "the pending set was not touched"
}

test_list_requires_an_initialized_project() {
  _test_setup list_uninit raw

  run_hm list

  assert_rc 3 "$HM_STATUS" "list fails on an uninitialized project"
  assert_contains "$HM_OUTPUT" "not initialized" "the error explains the problem"
}

test_list_fails_when_a_query_fails() {
  _list_fixture

  # The table of the overview does not exist any more, the command must
  # report the failure instead of printing an empty table.
  sqlite3 "$HM_DIR/db.sqlite" 'DROP TABLE generation_entries;'

  run_hm list

  assert_rc 5 "$HM_STATUS" "a failing query stops the command"
  assert_contains "$HM_OUTPUT" "Cannot read the generations" "the reason is named"
}

test_list_fails_when_a_count_query_fails() {
  _list_fixture

  # The pending set does not exist any more, the count of the pending paths
  # cannot be read.
  sqlite3 "$HM_DIR/db.sqlite" 'DROP TABLE pending_paths;'

  run_hm list --store

  assert_rc 5 "$HM_STATUS" "a failing count stops the command"
  assert_contains "$HM_OUTPUT" "Cannot read the database" "the reason is named"
}
