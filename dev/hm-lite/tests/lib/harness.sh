#!/usr/bin/env bash
#
# tests/lib/harness.sh - test harness.
#
# Provides assertions and per test isolation. Every test runs in its own
# temporary project directory, the real home directory is never touched.
#
# Environment provided by the runner:
#   HM_BIN     path of the hm executable under test
#   TEST_ROOT  root of the temporary test area
#

TESTS=()

# _test_setup [NAME] [MODE]
# Create a fresh, isolated project for the current test.
#
# MODE defaults to "init" and initializes the project so that the command
# under test finds a complete project directory. MODE "raw" leaves the
# project uninitialized, which is what the init tests need.
_test_setup() {
  local name="${1:-case}"
  local mode="${2:-init}"

  TEST_NAME="$name"
  TEST_DIR="$TEST_ROOT/work/$name"
  HM_DIR="$TEST_DIR/project"
  SRC_DIR="$TEST_DIR/source"
  DEST_DIR="$TEST_DIR/destination"
  CURRENT_DIR="$HM_DIR/current"
  TESTING_DIR="$HM_DIR/testing"
  STORE_DIR="$HM_DIR/store/objects"

  rm -rf -- "$TEST_DIR"
  mkdir -p -- "$HM_DIR" "$SRC_DIR" "$DEST_DIR"

  export HM_DIR
  unset HM_CODE_DIR

  if [[ "$mode" != "raw" ]]; then
    _test_init
  fi
}

# _test_init - initialize the project of the current test.
# The test fails when the initialization does not succeed.
_test_init() {
  run_hm init

  if [[ "$HM_STATUS" -ne 0 ]]; then
    _test_fail "the project initialization failed"
    printf '        output: %s\n' "${HM_OUTPUT:-}"
    return 1
  fi

  return 0
}

# _test_teardown - remove the isolated project of the current test.
_test_teardown() {
  if [[ -n "${TEST_DIR:-}" && "$TEST_DIR" == "$TEST_ROOT/work/"* ]]; then
    rm -rf -- "$TEST_DIR"
  fi
}

# --- Running the command under test ---------------------------------------

# run_hm ARGUMENTS...
# Runs hm, stores the combined output in HM_OUTPUT and the exit status in
# HM_STATUS. The function itself always succeeds so that a test can check
# the status.
run_hm() {
  local out status

  out="$("$HM_BIN" "$@" 2>&1)"
  status=$?

  HM_OUTPUT="$out"
  HM_STATUS="$status"
  return 0
}

# run_hm_input INPUT ARGUMENTS...
# Runs hm with INPUT on standard input, used for the confirmation prompts.
run_hm_input() {
  local input="$1"
  shift
  local out status

  out="$(printf '%s' "$input" | "$HM_BIN" "$@" 2>&1)"
  status=$?

  HM_OUTPUT="$out"
  HM_STATUS="$status"
  return 0
}

# --- Assertions ------------------------------------------------------------

_test_fail() {
  printf '      FAIL: %s\n' "$*"
  TEST_FAILURES=$((TEST_FAILURES + 1))
  return 1
}

_test_ok() {
  if [[ "${HM_TEST_VERBOSE:-0}" == "1" ]]; then
    printf '      ok: %s\n' "$*"
  fi
  return 0
}

# assert_eq EXPECTED ACTUAL MESSAGE
assert_eq() {
  local expected="$1" actual="$2" message="$3"

  if [[ "$expected" != "$actual" ]]; then
    _test_fail "$message"
    printf '        expected: [%s]\n' "$expected"
    printf '        actual:   [%s]\n' "$actual"
    return 1
  fi
  _test_ok "$message"
}

# assert_rc EXPECTED ACTUAL MESSAGE
assert_rc() {
  local expected="$1" actual="$2" message="$3"

  if [[ "$expected" != "$actual" ]]; then
    _test_fail "$message (exit status $actual, expected $expected)"
    printf '        output: %s\n' "${HM_OUTPUT:-}"
    return 1
  fi
  _test_ok "$message"
}

# assert_contains HAYSTACK NEEDLE MESSAGE
assert_contains() {
  local haystack="$1" needle="$2" message="$3"

  if [[ "$haystack" != *"$needle"* ]]; then
    _test_fail "$message"
    printf '        missing:  [%s]\n' "$needle"
    printf '        in output: [%s]\n' "$haystack"
    return 1
  fi
  _test_ok "$message"
}

# assert_not_contains HAYSTACK NEEDLE MESSAGE
assert_not_contains() {
  local haystack="$1" needle="$2" message="$3"

  if [[ "$haystack" == *"$needle"* ]]; then
    _test_fail "$message"
    printf '        unexpectedly found: [%s]\n' "$needle"
    return 1
  fi
  _test_ok "$message"
}

# assert_file_exists PATH MESSAGE
assert_file_exists() {
  local path="$1" message="$2"

  if [[ ! -e "$path" ]]; then
    _test_fail "$message"
    printf '        missing file: %s\n' "$path"
    return 1
  fi
  _test_ok "$message"
}

# assert_file_absent PATH MESSAGE
assert_file_absent() {
  local path="$1" message="$2"

  if [[ -e "$path" ]]; then
    _test_fail "$message"
    printf '        unexpected file: %s\n' "$path"
    return 1
  fi
  _test_ok "$message"
}

# assert_dir_empty PATH MESSAGE
assert_dir_empty() {
  local path="$1" message="$2"
  local count

  count="$(find "$path" -mindepth 1 -maxdepth 1 2>/dev/null | wc -l)"

  if [[ "$count" != "0" ]]; then
    _test_fail "$message"
    printf '        %s entries found in %s\n' "$count" "$path"
    return 1
  fi
  _test_ok "$message"
}

# assert_sql EXPECTED SQL MESSAGE
# Runs SQL directly against the project database, independent of the code
# under test.
assert_sql() {
  local expected="$1" sql="$2" message="$3"
  local actual

  actual="$(sqlite3 "$HM_DIR/db.sqlite" "$sql" 2>&1)"

  if [[ "$expected" != "$actual" ]]; then
    _test_fail "$message"
    printf '        expected: [%s]\n' "$expected"
    printf '        actual:   [%s]\n' "$actual"
    return 1
  fi
  _test_ok "$message"
}

# assert_file_content PATH EXPECTED_CONTENT MESSAGE
assert_file_content() {
  local path="$1" expected="$2" message="$3"
  local actual

  actual="$(cat -- "$path" 2>&1)"

  if [[ "$expected" != "$actual" ]]; then
    _test_fail "$message"
    printf '        expected: [%s]\n' "$expected"
    printf '        actual:   [%s]\n' "$actual"
    return 1
  fi
  _test_ok "$message"
}

# assert_count EXPECTED ACTUAL MESSAGE
assert_count() {
  local expected="$1" actual="$2" message="$3"

  if [[ "$expected" != "$actual" ]]; then
    _test_fail "$message"
    printf '        expected count: %s\n' "$expected"
    printf '        actual count:   %s\n' "$actual"
    return 1
  fi
  _test_ok "$message"
}
