#!/usr/bin/env bash
#
# tests/cases/12_color.sh - colour behaviour.
#
# The test list is read by the runner, shellcheck only sees this
# file and therefore reports the variable as unused.
# shellcheck disable=SC2034

TESTS=(
  test_color_is_off_when_the_output_is_not_a_terminal
  test_color_is_on_when_the_output_is_a_terminal
  test_hm_color_always_forces_the_colours
  test_hm_color_never_disables_the_colours
  test_no_color_disables_the_colours
  test_an_empty_no_color_does_not_disable_the_colours
  test_color_diagnostics_follow_standard_error
  test_colour_output_keeps_the_plain_output
  test_every_command_colours_its_output
  test_stdout_palette_follows_standard_output
)

# _color_fixture - one generation with one tracked file.
_color_fixture() {
  _test_setup color_fixture
  printf 'a\n' > "$SRC_DIR/a.txt"
  run_hm_input 'y\n' add "$SRC_DIR/a.txt"
  run_hm_input 'y\n' gen
}

# _color_run MODE NO_COLOR
# Run "hm show 1" with an explicit colour environment. NO_COLOR is unset
# when its value is __unset__, otherwise it is set to the given value.
_color_run() {
  local mode="$1" no_color="$2"
  local out status

  if [[ "$no_color" == "__unset__" ]]; then
    out="$(env -u NO_COLOR HM_COLOR="$mode" "$HM_BIN" show 1 2>&1 </dev/null)"
  else
    out="$(env NO_COLOR="$no_color" HM_COLOR="$mode" "$HM_BIN" show 1 2>&1 </dev/null)"
  fi
  status=$?

  HM_OUTPUT="$out"
  HM_STATUS="$status"
  return 0
}

# _color_has_script - report whether the util-linux "script" helper exists.
# The pseudo terminal tests are skipped without it.
_color_has_script() {
  if ! command -v script >/dev/null 2>&1; then
    printf '      SKIP script from util-linux is not installed, the pseudo terminal test is skipped.\n' >&2
    return 1
  fi
  return 0
}

test_color_is_off_when_the_output_is_not_a_terminal() {
  _color_fixture

  _color_run auto __unset__

  assert_rc 0 "$HM_STATUS" "show succeeds"
  assert_not_contains "$HM_OUTPUT" $'\033[' "no escape sequence is written to a pipe"
}

test_color_is_on_when_the_output_is_a_terminal() {
  _color_fixture
  _color_has_script || return 0

  local out
  out="$(env -u NO_COLOR HM_COLOR=auto script -qec "$HM_BIN show 1" /dev/null 2>&1)"

  assert_contains "$out" $'\033[1m' "the colours are enabled automatically on a terminal"
}

test_hm_color_always_forces_the_colours() {
  _color_fixture

  _color_run always __unset__

  assert_rc 0 "$HM_STATUS" "show succeeds"
  assert_contains "$HM_OUTPUT" $'\033[1m' "the heading is bold"
  assert_contains "$HM_OUTPUT" $'\033[0m' "the colour is reset"
}

test_hm_color_never_disables_the_colours() {
  _color_fixture

  _color_run never __unset__

  assert_rc 0 "$HM_STATUS" "show succeeds"
  assert_not_contains "$HM_OUTPUT" $'\033[' "no escape sequence is written"
}

test_no_color_disables_the_colours() {
  _color_fixture

  _color_run always 1
  assert_rc 0 "$HM_STATUS" "show succeeds"
  assert_not_contains "$HM_OUTPUT" $'\033[' "NO_COLOR wins over HM_COLOR=always"

  _color_run always 0
  assert_not_contains "$HM_OUTPUT" $'\033[' "any non-empty NO_COLOR disables the colours"
}

test_an_empty_no_color_does_not_disable_the_colours() {
  _color_fixture

  _color_run always ""

  assert_rc 0 "$HM_STATUS" "show succeeds"
  assert_contains "$HM_OUTPUT" $'\033[1m' "an empty NO_COLOR keeps the colours"
}

test_color_diagnostics_follow_standard_error() {
  _color_fixture
  _color_has_script || return 0

  local out
  out="$(env -u NO_COLOR HM_COLOR=auto script -qec "$HM_BIN clean --dry-run >/dev/null" /dev/null 2>&1)"

  assert_contains "$out" $'\033[' "the diagnostics are coloured when standard error is a terminal"
}

test_colour_output_keeps_the_plain_output() {
  _color_fixture

  local plain coloured stripped
  plain="$(env -u NO_COLOR HM_COLOR=never "$HM_BIN" show 1 2>&1 </dev/null)"
  coloured="$(env -u NO_COLOR HM_COLOR=always "$HM_BIN" show 1 2>&1 </dev/null)"
  stripped="$(printf '%s\n' "$coloured" | sed 's/\x1B\[[0-9;]*m//g')"

  assert_contains "$coloured" $'\033[' "the coloured output carries escape sequences"
  assert_eq "$plain" "$stripped" "stripping the colours restores the plain output"
}

# _color_stdout MODE ARGUMENTS... - run hm with an explicit colour mode and
# keep only standard output. The diagnostics never pollute the check.
_color_stdout() {
  local mode="$1"
  shift
  local out status

  out="$(env -u NO_COLOR HM_COLOR="$mode" "$HM_BIN" "$@" 2>/dev/null </dev/null)"
  status=$?

  HM_OUTPUT="$out"
  HM_STATUS="$status"
  return 0
}

# _color_stdout_input INPUT MODE ARGUMENTS... - the same with a prepared
# standard input.
_color_stdout_input() {
  local input="$1" mode="$2"
  shift 2
  local out status

  out="$(printf '%b' "$input" | env -u NO_COLOR HM_COLOR="$mode" "$HM_BIN" "$@" 2>/dev/null)"
  status=$?

  HM_OUTPUT="$out"
  HM_STATUS="$status"
  return 0
}

test_every_command_colours_its_output() {
  _test_setup color_every_command
  printf 'a\n' > "$SRC_DIR/a.txt"
  printf 'b\n' > "$SRC_DIR/b.txt"
  run_hm_input 'y\n' add "$SRC_DIR/a.txt"
  run_hm_input 'y\n' gen --name "first"

  _color_stdout always init
  assert_contains "$HM_OUTPUT" $'\033[' "hm init colours its output"

  _color_stdout_input 'y\n' always add "$SRC_DIR/b.txt"
  assert_contains "$HM_OUTPUT" $'\033[' "hm add colours its preview"

  _color_stdout_input 'y\n' always gen --name "second"
  assert_contains "$HM_OUTPUT" $'\033[' "hm gen colours its preview"

  _color_stdout always list
  assert_contains "$HM_OUTPUT" $'\033[' "hm list colours its table"

  _color_stdout always status
  assert_contains "$HM_OUTPUT" $'\033[' "hm status colours its dashboard"

  _color_stdout always show 1
  assert_contains "$HM_OUTPUT" $'\033[' "hm show colours its output"

  _color_stdout always diff 1 2
  assert_contains "$HM_OUTPUT" $'\033[' "hm diff colours its output"

  _color_stdout always edit 1 --name "renamed" --yes
  assert_contains "$HM_OUTPUT" $'\033[' "hm edit colours its preview"

  _color_stdout always switch 1
  assert_contains "$HM_OUTPUT" $'\033[' "hm switch colours its output"

  _color_stdout always apply 1 --dry-run
  assert_contains "$HM_OUTPUT" $'\033[' "hm apply colours its preview"

  _color_stdout always discard
  assert_contains "$HM_OUTPUT" $'\033[' "hm discard colours its output"

  _color_stdout always backup
  assert_contains "$HM_OUTPUT" $'\033[' "hm backup colours its summary"

  local archive
  archive="$(find "$HM_DIR/backup" -type f -name 'hm-backup-*.tar.gz' -print -quit)"
  assert_file_exists "$archive" "the backup archive exists"

  _color_stdout always restore "$archive" --yes
  assert_contains "$HM_OUTPUT" $'\033[' "hm restore colours its preview"

  _color_stdout always clean --dry-run
  assert_contains "$HM_OUTPUT" $'\033[' "hm clean colours its preview"

  _color_stdout always delete 2 --yes
  assert_contains "$HM_OUTPUT" $'\033[' "hm delete colours its preview"
}

test_stdout_palette_follows_standard_output() {
  _color_fixture
  _color_has_script || return 0

  local stdout_file="$TEST_DIR/stdout.txt"

  env -u NO_COLOR HM_COLOR=auto \
    script -qec "$HM_BIN add $SRC_DIR/a.txt >$stdout_file </dev/null" /dev/null \
    >/dev/null 2>&1

  assert_file_exists "$stdout_file" "the command wrote its standard output"
  assert_not_contains "$(cat -- "$stdout_file")" $'\033[' \
    "the output palette follows standard output, not standard error"
}
