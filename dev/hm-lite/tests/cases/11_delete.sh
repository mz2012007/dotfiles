#!/usr/bin/env bash
#
# tests/cases/11_delete.sh - delete behaviour.
#
# The test list is read by the runner, shellcheck only sees this
# file and therefore reports the variable as unused.
# shellcheck disable=SC2034

TESTS=(
  test_delete_removes_the_generation
  test_delete_removes_the_entries
  test_delete_keeps_the_other_generations
  test_delete_accepts_the_yes_flag
  test_delete_accepts_the_short_yes_flag
  test_delete_declining_changes_nothing
  test_delete_refuses_the_selected_generation
  test_delete_marks_the_children_as_parentless
  test_delete_rejects_an_unknown_generation
  test_delete_requires_a_generation
  test_delete_rejects_a_second_generation
  test_delete_rejects_unknown_options
  test_delete_leaves_the_orphans_to_clean
  test_delete_requires_an_initialized_project
  test_delete_fails_when_the_transaction_fails
)

# _delete_fixture - three generations, each one adds a path.
_delete_fixture() {
  _test_setup delete_fixture
  printf 'a\n' > "$SRC_DIR/a.txt"
  printf 'b\n' > "$SRC_DIR/b.txt"
  printf 'c\n' > "$SRC_DIR/c.txt"

  run_hm_input 'y\n' add "$SRC_DIR/a.txt"
  run_hm_input 'y\n' gen --name "one"

  run_hm_input 'y\n' add "$SRC_DIR/b.txt"
  run_hm_input 'y\n' gen --name "two"

  run_hm_input 'y\n' add "$SRC_DIR/c.txt"
  run_hm_input 'y\n' gen --name "three"
}

test_delete_removes_the_generation() {
  _delete_fixture

  run_hm_input 'y\n' delete 2

  assert_rc 0 "$HM_STATUS" "delete succeeds"
  assert_contains "$HM_OUTPUT" "Delete preview:" "the preview is shown"
  assert_sql "0" "SELECT COUNT(*) FROM generations WHERE id = 2;" "the generation is gone"
  assert_sql "2" "SELECT COUNT(*) FROM generations;" "the other generations are kept"
}

test_delete_removes_the_entries() {
  _delete_fixture

  run_hm_input 'y\n' delete 2

  assert_rc 0 "$HM_STATUS" "delete succeeds"
  assert_sql "0" "SELECT COUNT(*) FROM generation_entries WHERE generation_id = 2;" \
    "the entries of the generation are gone"
}

test_delete_keeps_the_other_generations() {
  _delete_fixture

  run_hm_input 'y\n' delete 2

  assert_rc 0 "$HM_STATUS" "delete succeeds"
  assert_sql "1" "SELECT COUNT(*) FROM generations WHERE id = 1;" "the parent stays"
  assert_sql "1" "SELECT COUNT(*) FROM generations WHERE id = 3;" "the child stays"
  assert_sql "3" "SELECT COUNT(*) FROM generation_entries WHERE generation_id = 3;" \
    "the entries of the child stay"
}

test_delete_accepts_the_yes_flag() {
  _delete_fixture

  run_hm delete 2 --yes

  assert_rc 0 "$HM_STATUS" "delete --yes does not ask"
  assert_sql "0" "SELECT COUNT(*) FROM generations WHERE id = 2;" "the generation is gone"
}

test_delete_accepts_the_short_yes_flag() {
  _delete_fixture

  run_hm delete 2 -y

  assert_rc 0 "$HM_STATUS" "delete -y does not ask"
  assert_sql "0" "SELECT COUNT(*) FROM generations WHERE id = 2;" "the generation is gone"
}

test_delete_declining_changes_nothing() {
  _delete_fixture

  run_hm_input 'n\n' delete 2

  assert_rc 7 "$HM_STATUS" "a declined confirmation is reported"
  assert_contains "$HM_OUTPUT" "Cancelled" "the command reports the cancellation"
  assert_sql "1" "SELECT COUNT(*) FROM generations WHERE id = 2;" "the generation is kept"
  assert_sql "2" "SELECT COUNT(*) FROM generation_entries WHERE generation_id = 2;" \
    "the entries are kept"
}

test_delete_refuses_the_selected_generation() {
  _delete_fixture

  run_hm switch 2
  assert_rc 0 "$HM_STATUS" "the fixture selects the generation"

  run_hm delete 2 --yes

  assert_rc 3 "$HM_STATUS" "the selected generation is refused"
  assert_contains "$HM_OUTPUT" "selected generation" "the error explains the rule"
  assert_sql "1" "SELECT COUNT(*) FROM generations WHERE id = 2;" "the generation is kept"
}

test_delete_marks_the_children_as_parentless() {
  _delete_fixture

  assert_sql "2" "SELECT parent_id FROM generations WHERE id = 3;" "the child has a parent"

  run_hm delete 2 --yes

  assert_rc 0 "$HM_STATUS" "delete succeeds"
  assert_sql "" "SELECT COALESCE(parent_id, '') FROM generations WHERE id = 3;" \
    "the parent of the child is cleared"
}

test_delete_rejects_an_unknown_generation() {
  _delete_fixture

  run_hm delete 99 --yes

  assert_rc 4 "$HM_STATUS" "an unknown generation is a state error"
  assert_contains "$HM_OUTPUT" "no generation" "the error explains the problem"
}

test_delete_requires_a_generation() {
  _delete_fixture

  run_hm delete

  assert_rc 2 "$HM_STATUS" "a missing generation is a usage error"
  assert_contains "$HM_OUTPUT" "Usage: hm delete" "the usage is printed"
}

test_delete_rejects_a_second_generation() {
  _delete_fixture

  run_hm delete 1 2 --yes

  assert_rc 2 "$HM_STATUS" "a second generation is a usage error"
  assert_contains "$HM_OUTPUT" "Usage: hm delete" "the usage is printed"
}

test_delete_rejects_unknown_options() {
  _delete_fixture

  run_hm delete --bogus 2

  assert_rc 2 "$HM_STATUS" "an unknown option is a usage error"
  assert_sql "3" "SELECT COUNT(*) FROM generations;" "nothing was deleted"
}

test_delete_leaves_the_orphans_to_clean() {
  _delete_fixture

  local hash
  hash="$(sqlite3 "$HM_DIR/db.sqlite" "
    SELECT f.hash
      FROM files f
      JOIN generation_entries ge ON ge.file_id = f.id
      JOIN paths p ON p.id = ge.path_id
     WHERE p.path = '$SRC_DIR/c.txt'
     LIMIT 1;")"
  [[ -n "$hash" ]] || { _test_fail "the fixture has no content object for c.txt"; return 0; }

  run_hm delete 3 --yes

  assert_rc 0 "$HM_STATUS" "delete succeeds"
  assert_contains "$HM_OUTPUT" "hm clean" "the follow up command is named"
  assert_file_exists "$STORE_DIR/${hash:0:2}/$hash" "the object stays until clean runs"

  run_hm clean --dry-run
  assert_rc 0 "$HM_STATUS" "the dry run succeeds"
  assert_contains "$HM_OUTPUT" "1 unreferenced object(s) in the store" "the orphan is found"
  assert_contains "$HM_OUTPUT" "1 unreferenced row(s) in the database" "the orphan row is found"

  run_hm clean -y
  assert_rc 0 "$HM_STATUS" "clean succeeds"
  assert_file_absent "$STORE_DIR/${hash:0:2}/$hash" "clean removes the orphan"
}

test_delete_requires_an_initialized_project() {
  _test_setup delete_uninit raw

  run_hm delete 1 --yes

  assert_rc 3 "$HM_STATUS" "delete fails on an uninitialized project"
  assert_contains "$HM_OUTPUT" "not initialized" "the error explains the problem"
}

test_delete_fails_when_the_transaction_fails() {
  _delete_fixture

  sqlite3 "$HM_DIR/db.sqlite" "
    CREATE TRIGGER hm_test_no_delete
    BEFORE DELETE ON generations
    BEGIN
      SELECT RAISE(ABORT, 'blocked for the test');
    END;"

  run_hm delete 2 --yes

  assert_rc 5 "$HM_STATUS" "a failing transaction is a database error"
  assert_sql "1" "SELECT COUNT(*) FROM generations WHERE id = 2;" "the generation is rolled back"
  assert_sql "2" "SELECT COUNT(*) FROM generation_entries WHERE generation_id = 2;" \
    "the entries are rolled back"
}
