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

# ---------------------------------------------------------------------------
# Static analysis
# ---------------------------------------------------------------------------

# The shell files of the project.
collect_shell_files() {
  printf '%s\n' \
    "$PROJECT_ROOT/hm" \
    "$PROJECT_ROOT"/lib/*.sh \
    "$PROJECT_ROOT"/core/*.sh \
    "$PROJECT_ROOT"/tests/run.sh \
    "$PROJECT_ROOT"/tests/lib/*.sh \
    "$PROJECT_ROOT"/tests/cases/*.sh
}

# run_syntax_check - every shell file must parse.
run_syntax_check() {
  local file failures=0

  while IFS= read -r file; do
    [[ -f "$file" ]] || continue
    if ! bash -n -- "$file"; then
      printf '  SYNTAX ERROR %s\n' "$file" >&2
      failures=$((failures + 1))
    fi
  done < <(collect_shell_files)

  return "$failures"
}

# run_shellcheck - the static analysis, when the tool is available.
run_shellcheck() {
  local file failures=0

  while IFS= read -r file; do
    [[ -f "$file" ]] || continue
    if ! shellcheck -x -S style -e SC1090,SC1091 -- "$file"; then
      failures=$((failures + 1))
    fi
  done < <(collect_shell_files)

  return "$failures"
}

printf '\n== static analysis\n'

total=$((total + 1))

if run_syntax_check; then
  passed=$((passed + 1))
  printf '  PASS every shell file parses\n'
else
  failed=$((failed + 1))
  failed_names+=("static analysis: syntax")
  printf '  FAIL a shell file does not parse\n'
fi

if command -v shellcheck > /dev/null 2>&1; then
  total=$((total + 1))

  if run_shellcheck; then
    passed=$((passed + 1))
    printf '  PASS shellcheck found no problem\n'
  else
    failed=$((failed + 1))
    failed_names+=("static analysis: shellcheck")
    printf '  FAIL shellcheck found a problem\n'
  fi
else
  printf '  SKIP shellcheck is not installed, the static analysis was not run.\n'
fi

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
