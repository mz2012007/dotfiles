#!/usr/bin/env bash
#
# tests/cases/06_apply.sh - apply behaviour.
#
# The test list is read by the runner, shellcheck only sees this
# file and therefore reports the variable as unused.
# shellcheck disable=SC2034

TESTS=(
  test_apply_creates_a_missing_file
  test_apply_updates_a_changed_file
  test_apply_leaves_an_unchanged_file_alone
  test_apply_restores_the_recorded_mode
  test_apply_backs_up_the_overwritten_file
  test_apply_writes_a_manifest
  test_apply_refuses_a_symbolic_link
  test_apply_refuses_a_type_conflict
  test_apply_refuses_a_path_outside_the_home_directory
  test_apply_refuses_the_filesystem_root
  test_apply_declining_changes_nothing
  test_apply_dry_run_changes_nothing
  test_apply_uses_the_selected_generation
  test_apply_rejects_an_unknown_generation
  test_apply_requires_a_generation
  test_apply_rolls_back_after_a_failure
)

# _apply_fixture - one generation with one file.
_apply_fixture() {
  _test_setup apply_fixture
  printf 'original\n' > "$SRC_DIR/a.txt"

  run_hm_input 'y
' add "$SRC_DIR/a.txt"
  run_hm_input 'y
' gen
}

test_apply_creates_a_missing_file() {
  _apply_fixture
  rm -f -- "$SRC_DIR/a.txt"

  run_hm_input 'y
' apply 1

  assert_rc 0 "$HM_STATUS" "apply succeeds"
  assert_file_exists "$SRC_DIR/a.txt" "the file was created"
  assert_file_content "$SRC_DIR/a.txt" "original" "the content was written"
}

test_apply_updates_a_changed_file() {
  _apply_fixture
  printf 'changed\n' > "$SRC_DIR/a.txt"

  run_hm_input 'y
' apply 1

  assert_rc 0 "$HM_STATUS" "apply succeeds"
  assert_file_content "$SRC_DIR/a.txt" "original" "the file was restored"
  assert_contains "$HM_OUTPUT" "UPDATE" "the update was announced"
}

test_apply_leaves_an_unchanged_file_alone() {
  _apply_fixture
  local before after

  before="$(stat -c '%Y' -- "$SRC_DIR/a.txt")"

  run_hm_input 'y
' apply 1

  after="$(stat -c '%Y' -- "$SRC_DIR/a.txt")"

  assert_rc 0 "$HM_STATUS" "apply succeeds"
  assert_eq "$before" "$after" "the file was not written again"
  assert_contains "$HM_OUTPUT" "UNCHANGED" "the unchanged file was reported"
}

test_apply_restores_the_recorded_mode() {
  _apply_fixture
  chmod 600 -- "$SRC_DIR/a.txt"

  run_hm_input 'y
' apply 1

  assert_rc 0 "$HM_STATUS" "apply succeeds"
  assert_eq "644" "$(stat -c '%a' -- "$SRC_DIR/a.txt")" "the recorded mode was restored"
}

test_apply_backs_up_the_overwritten_file() {
  _apply_fixture
  printf 'changed\n' > "$SRC_DIR/a.txt"

  run_hm_input 'y
' apply 1

  assert_rc 0 "$HM_STATUS" "apply succeeds"
  local backup
  backup="$(printf '%s\n' "$HM_OUTPUT" | sed -n 's/^Backup:[[:space:]]*//p')"

  assert_count "1" "$(find "$backup/files" -type f | wc -l)" "the overwritten file was backed up"
  assert_file_content "$backup/files/0001" "changed" "the backup holds the previous content"
}

test_apply_writes_a_manifest() {
  _apply_fixture
  printf 'changed\n' > "$SRC_DIR/a.txt"

  run_hm_input 'y
' apply 1

  assert_rc 0 "$HM_STATUS" "apply succeeds"
  local backup manifest
  backup="$(printf '%s\n' "$HM_OUTPUT" | sed -n 's/^Backup:[[:space:]]*//p')"
  manifest="$backup/manifest.tsv"

  assert_file_exists "$manifest" "the manifest was written"
  assert_contains "$(cat -- "$manifest")" "update" "the manifest records the update"
}

test_apply_refuses_a_symbolic_link() {
  _apply_fixture
  rm -f -- "$SRC_DIR/a.txt"
  ln -s /etc/passwd "$SRC_DIR/a.txt"

  run_hm_input 'y
' apply 1

  assert_rc 3 "$HM_STATUS" "apply refuses a symbolic link"
  assert_contains "$HM_OUTPUT" "symbolic link" "the reason is named"
  assert_eq "/etc/passwd" "$(readlink -- "$SRC_DIR/a.txt")" "the link was not written through"
}

test_apply_refuses_a_type_conflict() {
  _apply_fixture
  rm -f -- "$SRC_DIR/a.txt"
  mkdir -p -- "$SRC_DIR/a.txt"

  run_hm_input 'y
' apply 1

  assert_rc 3 "$HM_STATUS" "apply refuses a type conflict"
  assert_contains "$HM_OUTPUT" "CONFLICT" "the conflict is reported"
  assert_dir_empty "$SRC_DIR/a.txt" "the directory was not touched"
}

test_apply_refuses_a_path_outside_the_home_directory() {
  _apply_fixture
  unset HM_ALLOW_OUTSIDE_HOME

  run_hm_input 'y
' apply 1

  assert_rc 3 "$HM_STATUS" "apply refuses a path outside of the home directory"
  assert_contains "$HM_OUTPUT" "outside of the home directory" "the reason is named"
}

test_apply_refuses_the_filesystem_root() {
  _apply_fixture

  # The recorded path is changed to the root of the filesystem, the apply
  # must refuse such a destination even when the home restriction is off.
  sqlite3 "$HM_DIR/db.sqlite" \
    "UPDATE paths SET path = '/' WHERE path = '$SRC_DIR/a.txt';"

  run_hm_input 'y
' apply 1

  assert_rc 3 "$HM_STATUS" "apply refuses the root of the filesystem"
  assert_contains "$HM_OUTPUT" "safe destination" "the reason is named"
}

test_apply_declining_changes_nothing() {
  _apply_fixture
  printf 'changed\n' > "$SRC_DIR/a.txt"

  run_hm_input 'n
' apply 1

  assert_rc 7 "$HM_STATUS" "the decline is reported with its own exit code"
  assert_file_content "$SRC_DIR/a.txt" "changed" "the file was not changed"
}

test_apply_dry_run_changes_nothing() {
  _apply_fixture
  printf 'changed\n' > "$SRC_DIR/a.txt"

  run_hm_input 'y
' apply 1 --dry-run

  assert_rc 0 "$HM_STATUS" "the dry run succeeds"
  assert_contains "$HM_OUTPUT" "UPDATE" "the preview shows the update"
  assert_file_content "$SRC_DIR/a.txt" "changed" "the file was not changed"
}

test_apply_uses_the_selected_generation() {
  _apply_fixture
  printf 'second\n' > "$SRC_DIR/b.txt"
  run_hm_input 'y
' add "$SRC_DIR/b.txt"
  run_hm_input 'y
' gen

  run_hm switch 2
  assert_rc 0 "$HM_STATUS" "switch succeeds"

  run_hm_input 'y
' apply

  assert_rc 0 "$HM_STATUS" "apply succeeds"
  assert_file_content "$SRC_DIR/a.txt" "original" "the file of the generation was written"
  assert_file_content "$SRC_DIR/b.txt" "second" "the new file was written"
}

test_apply_rejects_an_unknown_generation() {
  _apply_fixture

  run_hm apply 42

  assert_rc 4 "$HM_STATUS" "an unknown generation is a state error"
}

test_apply_requires_a_generation() {
  _apply_fixture

  run_hm_input 'y
' apply

  assert_rc 4 "$HM_STATUS" "apply without a selected generation is a state error"
  assert_contains "$HM_OUTPUT" "No generation is selected" "the error explains the problem"
}

test_apply_rolls_back_after_a_failure() {
  _test_setup apply_rollback
  mkdir -p "$SRC_DIR/locked"
  printf 'first\n' > "$SRC_DIR/a.txt"
  printf 'second\n' > "$SRC_DIR/locked/b.txt"

  run_hm_input 'y
' add "$SRC_DIR"
  run_hm_input 'y
' gen
  assert_rc 0 "$HM_STATUS" "the generation was created"

  printf 'changed\n' > "$SRC_DIR/a.txt"
  printf 'changed\n' > "$SRC_DIR/locked/b.txt"
  chmod 500 -- "$SRC_DIR/locked"

  run_hm_input 'y
' apply 1

  chmod 755 -- "$SRC_DIR/locked"

  assert_rc 9 "$HM_STATUS" "apply fails with the input/output status"
  assert_file_content "$SRC_DIR/a.txt" "changed" "the first file was restored"
}
