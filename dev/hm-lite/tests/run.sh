#!/usr/bin/env bash
#
# tests/run.sh - test runner.
#
# Every test case runs in its own temporary project directory. The runner
# creates one unique temporary root for the whole run and removes it again
# afterwards, the real home directory is never touched.
#
# Usage:
#   tests/run.sh              run all test cases
#   tests/run.sh 03_gen.sh    run the matching test case files only
#
set -uo pipefail

HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
PROJECT_ROOT="$(dirname -- "$HERE")"

export HM_BIN="$PROJECT_ROOT/hm"
export TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/hm-lite-tests.XXXXXXXX")"

cleanup() {
  rm -rf -- "$TEST_ROOT"
}
trap cleanup EXIT

if [[ ! -x "$HM_BIN" ]]; then
  printf 'The hm executable is missing or not executable: %s\n' "$HM_BIN" >&2
  exit 1
fi

total=0
passed=0
failed=0
failed_names=()

filter="${1:-}"

for case_file in "$HERE"/cases/*.sh; do
  [[ -f "$case_file" ]] || continue

  name="$(basename -- "$case_file")"
  if [[ -n "$filter" && "$name" != *"$filter"* ]]; then
    continue
  fi

  printf '\n== %s\n' "$name"

  # Source the case file to learn the list of tests.
  TESTS=()
  # shellcheck source=/dev/null
  source "$case_file"

  for test_name in "${TESTS[@]}"; do
    total=$((total + 1))

    output="$(
      set +e
      source "$HERE/lib/harness.sh"
      # shellcheck source=/dev/null
      source "$case_file"
      TEST_FAILURES=0
      "$test_name"
      exit $((TEST_FAILURES > 0 ? 1 : 0))
    )"
    status=$?

    if [[ $status -eq 0 ]]; then
      passed=$((passed + 1))
      printf '  PASS %s\n' "$test_name"
    else
      failed=$((failed + 1))
      failed_names+=("$test_name")
      printf '  FAIL %s\n' "$test_name"
      printf '%s\n' "$output"
    fi
  done
done

printf '\n---------------------------------------------\n'
printf 'total: %d   passed: %d   failed: %d\n' "$total" "$passed" "$failed"

if [[ $failed -gt 0 ]]; then
  printf 'failed tests:\n'
  for test_name in "${failed_names[@]}"; do
    printf '  - %s\n' "$test_name"
  done
  exit 1
fi

exit 0
