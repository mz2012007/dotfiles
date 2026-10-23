#!/usr/bin/env bash
#
# tests/cases/18_profile_roots.sh - profile roots and local generation numbers.
#
# A profile owns a root directory and its own generation sequence. A number
# such as 1 identifies a generation only inside a profile, the content store
# stays shared.
# shellcheck disable=SC2034

TESTS=(
  test_profile_create_stores_the_root
  test_profile_list_and_show_print_the_root
  test_profile_create_requires_an_existing_directory
  test_add_rejects_a_path_outside_the_root
  test_add_accepts_a_path_inside_the_root
  test_generation_numbers_are_local_to_each_profile
  test_generation_commands_resolve_local_numbers
  test_generation_numbers_are_not_reused_after_delete
  test_apply_rejects_an_entry_outside_the_root
  test_profile_create_help_is_available
)

# _roots_fixture - two profiles with independent roots and generations.
#
#   profile test: test-root/sub/a.txt, test-root/sub/b.txt  (1, 2)
#   profile dev:  dev-root/d.txt                           (1)
#
# The internal identifiers are 1, 2 and 3, the local numbers are 1, 2 and 1.
_roots_fixture() {
  _test_setup profile_roots_fixture
  mkdir -p "$SRC_DIR/test-root/sub" "$SRC_DIR/dev-root"
  printf 'one\n' > "$SRC_DIR/test-root/sub/a.txt"
  printf 'two\n' > "$SRC_DIR/test-root/sub/b.txt"
  printf 'dev\n' > "$SRC_DIR/dev-root/d.txt"

  run_hm profile create test "$SRC_DIR/test-root"
  run_hm_input 'y\n' add --profile test "$SRC_DIR/test-root/sub/a.txt"
  run_hm_input 'y\n' gen --profile test --name "test-1"
  run_hm_input 'y\n' add --profile test "$SRC_DIR/test-root/sub/b.txt"
  run_hm_input 'y\n' gen --profile test --name "test-2"

  run_hm profile create dev "$SRC_DIR/dev-root"
  run_hm_input 'y\n' add --profile dev "$SRC_DIR/dev-root/d.txt"
  run_hm_input 'y\n' gen --profile dev --name "dev-1"
}

test_profile_create_stores_the_root() {
  _test_setup profile_create_root
  mkdir -p "$SRC_DIR/project"

  run_hm profile create test "$SRC_DIR/project/"

  assert_rc 0 "$HM_STATUS" "profile create succeeds"
  assert_sql "$SRC_DIR/project" \
    "SELECT root FROM profiles WHERE name = 'test';" \
    "the normalized root is stored"
  assert_sql "1" \
    "SELECT next_generation_number FROM profiles WHERE name = 'test';" \
    "the local generation sequence starts at one"
  assert_contains "$HM_OUTPUT" "Root:" "the output names the root"
  assert_contains "$HM_OUTPUT" "$SRC_DIR/project" "the output prints the root"
  assert_sql "1" "SELECT COUNT(*) FROM profiles WHERE name = 'test';" \
    "the profile was created"
}

test_profile_list_and_show_print_the_root() {
  _test_setup profile_roots_output
  mkdir -p "$SRC_DIR/output-root"

  run_hm profile create output "$SRC_DIR/output-root"

  run_hm profile list
  assert_rc 0 "$HM_STATUS" "profile list succeeds"
  assert_contains "$HM_OUTPUT" "ROOT" "the list has a root column"
  assert_contains "$HM_OUTPUT" "$SRC_DIR/output-root" "the list prints the root"

  run_hm profile show output
  assert_rc 0 "$HM_STATUS" "profile show succeeds"
  assert_contains "$HM_OUTPUT" "Root:" "the profile details print the root"
  assert_contains "$HM_OUTPUT" "$SRC_DIR/output-root" "the details print the root"
}

test_profile_create_requires_an_existing_directory() {
  _test_setup profile_create_missing

  run_hm profile create missing "$SRC_DIR/without-root"

  assert_rc 3 "$HM_STATUS" "a missing root is a validation error"
  assert_contains "$HM_OUTPUT" "root" "the error mentions the root"
  assert_contains "$HM_OUTPUT" "directory" "the error explains the expectation"
  assert_sql "0" "SELECT COUNT(*) FROM profiles WHERE name = 'missing';" \
    "the profile was not created"
}

test_add_rejects_a_path_outside_the_root() {
  _test_setup profile_root_add_outside
  mkdir -p "$SRC_DIR/allowed"
  printf 'outside\n' > "$SRC_DIR/outside.txt"

  run_hm profile create guarded "$SRC_DIR/allowed"
  run_hm_input 'y\n' add --profile guarded "$SRC_DIR/outside.txt"

  assert_rc 3 "$HM_STATUS" "a path outside the root is refused"
  assert_contains "$HM_OUTPUT" "outside" "the error names the offending path"
  assert_contains "$HM_OUTPUT" "$SRC_DIR/allowed" "the error names the root"
  assert_sql "0" "SELECT COUNT(*) FROM paths WHERE path = '$SRC_DIR/outside.txt';" \
    "the path was not registered"
  assert_sql "0" "SELECT COUNT(*) FROM pending_paths;" \
    "the path was not queued"
}

test_add_accepts_a_path_inside_the_root() {
  _test_setup profile_root_add_inside
  mkdir -p "$SRC_DIR/allowed/sub"
  printf 'inside\n' > "$SRC_DIR/allowed/sub/file.txt"

  run_hm profile create guarded "$SRC_DIR/allowed"
  run_hm_input 'y\n' add --profile guarded "$SRC_DIR/allowed/sub/file.txt"

  assert_rc 0 "$HM_STATUS" "a path inside the root is accepted"
  assert_sql "1" \
    "SELECT COUNT(*) FROM path_profiles x JOIN profiles pr ON pr.id = x.profile_id
      WHERE pr.name = 'guarded';" \
    "the path belongs to the profile"
  assert_sql "1" \
    "SELECT COUNT(*) FROM pending_paths pp JOIN profiles pr ON pr.id = pp.profile_id
      WHERE pr.name = 'guarded';" \
    "the path is pending in the profile"
}

test_generation_numbers_are_local_to_each_profile() {
  _roots_fixture

  assert_sql "1" \
    "SELECT number FROM generations g JOIN profiles pr ON pr.id = g.profile_id
      WHERE pr.name = 'test' AND g.id = 1;" \
    "the first test generation is number one"
  assert_sql "2" \
    "SELECT number FROM generations g JOIN profiles pr ON pr.id = g.profile_id
      WHERE pr.name = 'test' AND g.id = 2;" \
    "the second test generation is number two"
  assert_sql "1" \
    "SELECT number FROM generations g JOIN profiles pr ON pr.id = g.profile_id
      WHERE pr.name = 'dev' AND g.id = 3;" \
    "the development generation is also number one"
  assert_sql "2" \
    "SELECT COUNT(*) FROM generations g JOIN profiles pr ON pr.id = g.profile_id
      WHERE pr.name = 'test';" \
    "the first profile has two generations"
  assert_sql "1" \
    "SELECT COUNT(*) FROM generations g JOIN profiles pr ON pr.id = g.profile_id
      WHERE pr.name = 'dev';" \
    "the second profile has one generation"
}

test_generation_commands_resolve_local_numbers() {
  _roots_fixture

  run_hm show --profile test 2
  assert_rc 0 "$HM_STATUS" "show resolves the local number"
  assert_contains "$HM_OUTPUT" "Generation 2" "the local number is printed"
  assert_contains "$HM_OUTPUT" "test-2" "the generation of the profile is shown"
  assert_not_contains "$HM_OUTPUT" "dev-1" "the other profile is not shown"

  run_hm show --profile dev 1
  assert_rc 0 "$HM_STATUS" "the other profile has its own number one"
  assert_contains "$HM_OUTPUT" "dev-1" "the development generation is shown"

  run_hm show --profile test 3
  assert_rc 4 "$HM_STATUS" "a number that the profile does not have is a state error"
  assert_contains "$HM_OUTPUT" "no generation" "the error explains the missing number"

  run_hm switch --profile test 2
  assert_rc 0 "$HM_STATUS" "switch resolves the local number"
  assert_sql "2" "SELECT value FROM state WHERE key = 'selected_generation:test';" \
    "the internal identifier of the local generation is stored"

  run_hm switch --profile dev 1
  assert_rc 0 "$HM_STATUS" "switch resolves the other profile number one"
  assert_sql "3" "SELECT value FROM state WHERE key = 'selected_generation:dev';" \
    "the other profile selection is independent"
  assert_sql "2" "SELECT value FROM state WHERE key = 'selected_generation:test';" \
    "the first profile selection is kept"
}

test_generation_numbers_are_not_reused_after_delete() {
  _roots_fixture
  mkdir -p "$SRC_DIR/test-root/sub"
  printf 'three\n' > "$SRC_DIR/test-root/sub/c.txt"

  run_hm switch --profile test 1
  run_hm delete --profile test 2 --yes
  assert_rc 0 "$HM_STATUS" "the second generation is deleted"

  run_hm_input 'y\n' add --profile test "$SRC_DIR/test-root/sub/c.txt"
  run_hm_input 'y\n' gen --profile test --name "test-3"

  assert_sql "3" \
    "SELECT number FROM generations g JOIN profiles pr ON pr.id = g.profile_id
      WHERE pr.name = 'test' AND g.name = 'test-3';" \
    "the deleted number is not reused"
  assert_sql "4" "SELECT next_generation_number FROM profiles WHERE name = 'test';" \
    "the local sequence advanced"
}

test_apply_rejects_an_entry_outside_the_root() {
  _test_setup profile_root_apply
  mkdir -p "$SRC_DIR/project/sub"
  printf 'apply\n' > "$SRC_DIR/project/file.txt"

  run_hm profile create guarded "$SRC_DIR/project"
  run_hm_input 'y\n' add --profile guarded "$SRC_DIR/project/file.txt"
  run_hm_input 'y\n' gen --profile guarded --name "apply-1"

  # Simulate a root that moved after the generation was captured. The apply
  # command has to refuse the entry instead of writing outside the root.
  sqlite3 "$HM_DIR/db.sqlite" \
    "UPDATE profiles SET root = '$SRC_DIR/project/sub' WHERE name = 'guarded';"

  run_hm apply --profile guarded --dry-run 1

  assert_rc 3 "$HM_STATUS" "apply refuses an entry outside the profile root"
  assert_contains "$HM_OUTPUT" "CONFLICT" "the entry is marked as a conflict"
  assert_contains "$HM_OUTPUT" "root" "the conflict reason mentions the root"
  assert_not_contains "$HM_OUTPUT" "CREATE  $SRC_DIR/project/file.txt" \
    "the outside path is not scheduled for creation"
}

test_profile_create_help_is_available() {
  _test_setup profile_create_help raw

  run_hm profile create --help
  assert_rc 0 "$HM_STATUS" "profile create help succeeds"
  assert_contains "$HM_OUTPUT" "profile create" "the help names the command"
  assert_contains "$HM_OUTPUT" "ROOT" "the help documents the root"
}
