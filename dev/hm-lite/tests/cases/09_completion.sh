#!/usr/bin/env bash
#
# tests/cases/09_completion.sh - the shell completion files.
#
# The bash completion is executed directly, the fish completion is executed
# through "complete -C", the zsh completion is executed only when zsh is
# installed. A missing shell is reported on stderr and the test passes, so
# that the report of the run documents the work that was not executed.
#
# The test list is read by the runner, shellcheck only sees this file and
# therefore reports the variable as unused.
# shellcheck disable=SC2034

TESTS=(
  test_completion_files_are_present
  test_completion_bash_offers_the_commands
  test_completion_bash_offers_the_options_of_each_command
  test_completion_bash_does_not_offer_unsupported_options
  test_completion_bash_does_not_offer_arguments_out_of_range
  test_completion_bash_offers_the_generation_ids
  test_completion_bash_offers_the_profile_names
  test_completion_bash_completes_the_inline_generation_option
  test_completion_bash_offers_the_tracked_paths
  test_completion_bash_keeps_paths_with_spaces
  test_completion_bash_offers_the_backup_archives
  test_completion_bash_fails_safe_without_a_database
  test_completion_bash_does_not_modify_the_project
  test_completion_fish_offers_the_commands
  test_completion_fish_offers_the_options_of_each_command
  test_completion_fish_offers_the_generation_ids
  test_completion_fish_does_not_offer_arguments_out_of_range
  test_completion_zsh_syntax
  test_completion_zsh_registers_the_completion
)

# _completion_root - the root directory of the project under test.
_completion_root() {
  dirname -- "$HM_BIN"
}

# _completion_bash WORD...
# Run the bash completion with the words and print the candidates, one per
# line. The last word is the word that is being completed.
_completion_bash() {
  local root
  root="$(_completion_root)"

  bash --norc --noprofile -c '
    source "$1/completions/hm.bash" || exit 1
    shift

    COMP_WORDS=("$@")
    COMP_CWORD=$(( $# - 1 ))
    COMPREPLY=()
    _hm

    if (( ${#COMPREPLY[@]} > 0 )); then
      printf "%s\n" "${COMPREPLY[@]}"
    fi
  ' bash "$root" "$@"
}

# _completion_fish LINE
# Run the fish completion of the command line and print the candidates.
_completion_fish() {
  local root
  root="$(_completion_root)"

  # The script is fish code, the variables belong to fish.
  # shellcheck disable=SC2016
  fish --no-config -c '
    source $argv[1]/completions/hm.fish
    complete -C $argv[2]
  ' "$root" "$1" | cut -f 1
}

# _completion_fish_available - the fish completion can be executed.
_completion_fish_available() {
  command -v fish > /dev/null 2>&1
}

# _completion_zsh_available - the zsh completion can be executed.
_completion_zsh_available() {
  command -v zsh > /dev/null 2>&1
}

# _completion_fixture - two generations, a space and a quote in a file name.
_completion_fixture() {
  _test_setup completion_fixture

  mkdir -p "$SRC_DIR/dir with space"
  printf 'hello\n' > "$SRC_DIR/a.txt"
  printf 'world\n' > "$SRC_DIR/dir with space/b'q.txt"

  run_hm_input 'y\n' add "$SRC_DIR"
  run_hm_input 'y\n' gen

  printf 'second\n' > "$SRC_DIR/second.txt"
  run_hm_input 'y\n' add "$SRC_DIR/second.txt"
  run_hm_input 'y\n' gen
}

# _completion_state - a fingerprint of the state of the project.
_completion_state() {
  local file

  {
    while IFS= read -r file; do
      printf '%s %s\n' "$file" "$(sha256sum -- "$file")"
    done < <(find "$HM_DIR" -type f | sort)

    sqlite3 "$HM_DIR/db.sqlite" \
      'SELECT count(*) FROM generations; SELECT count(*) FROM paths;'
  } | sha256sum
}

# --- The completion files --------------------------------------------------

test_completion_files_are_present() {
  local root
  root="$(_completion_root)"

  assert_file_exists "$root/completions/hm.bash" "the bash completion is present"
  assert_file_exists "$root/completions/hm.fish" "the fish completion is present"
  assert_file_exists "$root/completions/hm.zsh" "the zsh completion is present"
}

# --- The bash completion ---------------------------------------------------

test_completion_bash_offers_the_commands() {
  local candidates

  _test_setup completion_commands

  candidates="$(_completion_bash hm '')"

  assert_contains "$candidates" "init" "the completion offers init"
  assert_contains "$candidates" "add" "the completion offers add"
  assert_contains "$candidates" "gen" "the completion offers gen"
  assert_contains "$candidates" "list" "the completion offers list"
  assert_contains "$candidates" "status" "the completion offers status"
  assert_contains "$candidates" "show" "the completion offers show"
  assert_contains "$candidates" "edit" "the completion offers edit"
  assert_contains "$candidates" "diff" "the completion offers diff"
  assert_contains "$candidates" "switch" "the completion offers switch"
  assert_contains "$candidates" "delete" "the completion offers delete"
  assert_contains "$candidates" "apply" "the completion offers apply"
  assert_contains "$candidates" "discard" "the completion offers discard"
  assert_contains "$candidates" "backup" "the completion offers backup"
  assert_contains "$candidates" "restore" "the completion offers restore"
  assert_contains "$candidates" "clean" "the completion offers clean"
  assert_contains "$candidates" "help" "the completion offers help"
  assert_contains "$candidates" "--version" "the completion offers --version"
  assert_not_contains "$candidates" "install" "the completion offers no phantom command"
  assert_not_contains "$candidates" "remove" "the completion offers no phantom command"
}

test_completion_bash_offers_the_options_of_each_command() {
  local candidates

  _test_setup completion_options

  candidates="$(_completion_bash hm gen '--' | tr '\n' ' ')"
  assert_eq "--profile --name --comment --yes --help " "$candidates" \
    "gen offers its long options"

  candidates="$(_completion_bash hm list '--' | tr '\n' ' ')"
  assert_eq "--profile --generation --pending --paths --store --help " "$candidates" \
    "list offers its long options"

  candidates="$(_completion_bash hm apply '--' | tr '\n' ' ')"
  assert_eq "--profile --dry-run --yes --help " "$candidates" \
    "apply offers its long options"

  candidates="$(_completion_bash hm add '--' | tr '\n' ' ')"
  assert_eq "--profile --help " "$candidates" \
    "add offers its long options"

  candidates="$(_completion_bash hm clean '--' | tr '\n' ' ')"
  assert_eq "--dry-run --yes --help " "$candidates" \
    "clean offers its long options"

  candidates="$(_completion_bash hm restore '--' | tr '\n' ' ')"
  assert_eq "--yes --help " "$candidates" \
    "restore offers its long options"

  candidates="$(_completion_bash hm delete '--' | tr '\n' ' ')"
  assert_eq "--yes --help " "$candidates" \
    "delete offers its long options"

  candidates="$(_completion_bash hm show '--' | tr '\n' ' ')"
  assert_eq "--help " "$candidates" \
    "show offers only the help option"

  candidates="$(_completion_bash hm status '--' | tr '\n' ' ')"
  assert_eq "--profile --help " "$candidates" \
    "status offers its long options"

  candidates="$(_completion_bash hm edit '--' | tr '\n' ' ')"
  assert_eq "--name --comment --clear-name --clear-comment --yes --help " "$candidates" \
    "edit offers its long options"

  candidates="$(_completion_bash hm diff '--' | tr '\n' ' ')"
  assert_eq "--all --help " "$candidates" \
    "diff offers its long options"

  candidates="$(_completion_bash hm init '--' | tr '\n' ' ')"
  assert_eq "--help " "$candidates" \
    "init offers only the help option"

  candidates="$(_completion_bash hm backup '--' | tr '\n' ' ')"
  assert_eq "--help " "$candidates" \
    "backup offers only the help option"
}

test_completion_bash_does_not_offer_unsupported_options() {
  local candidates

  _test_setup completion_unsupported

  candidates="$(_completion_bash hm backup '--')"
  assert_not_contains "$candidates" "--yes" "backup does not offer --yes"
  assert_not_contains "$candidates" "--dry-run" "backup does not offer --dry-run"

  candidates="$(_completion_bash hm list '--')"
  assert_not_contains "$candidates" "--yes" "list does not offer --yes"
  assert_not_contains "$candidates" "--dry-run" "list does not offer --dry-run"

  candidates="$(_completion_bash hm switch '--')"
  assert_not_contains "$candidates" "--yes" "switch does not offer --yes"
  assert_not_contains "$candidates" "--dry-run" "switch does not offer --dry-run"

  candidates="$(_completion_bash hm show '--')"
  assert_not_contains "$candidates" "--yes" "show does not offer --yes"

  candidates="$(_completion_bash hm edit '--')"
  assert_not_contains "$candidates" "--dry-run" "edit does not offer --dry-run"

  candidates="$(_completion_bash hm diff '--')"
  assert_not_contains "$candidates" "--yes" "diff does not offer --yes"

  candidates="$(_completion_bash hm status '--')"
  assert_not_contains "$candidates" "--yes" "status does not offer --yes"
  assert_not_contains "$candidates" "--dry-run" "status does not offer --dry-run"

  candidates="$(_completion_bash hm gen '--')"
  assert_not_contains "$candidates" "--dry-run" "gen does not offer --dry-run"
}

test_completion_bash_does_not_offer_arguments_out_of_range() {
  local candidates

  _completion_fixture

  candidates="$(_completion_bash hm switch 1 '')"
  assert_eq "" "$candidates" "switch offers nothing after its generation"

  candidates="$(_completion_bash hm show 1 '')"
  assert_eq "" "$candidates" "show offers nothing after its generation"

  candidates="$(_completion_bash hm edit 1 '')"
  assert_eq "" "$candidates" "edit offers nothing after its generation"

  candidates="$(_completion_bash hm delete 1 '')"
  assert_eq "" "$candidates" "delete offers nothing after its generation"

  candidates="$(_completion_bash hm apply 1 '')"
  assert_eq "" "$candidates" "apply offers nothing after its generation"

  candidates="$(_completion_bash hm init '')"
  assert_eq "" "$candidates" "init offers no argument"

  candidates="$(_completion_bash hm backup '')"
  assert_eq "" "$candidates" "backup offers no argument"

  candidates="$(_completion_bash hm gen '')"
  assert_eq "" "$candidates" "gen offers no argument"

  candidates="$(_completion_bash hm list '')"
  assert_eq "" "$candidates" "list offers no argument"

  candidates="$(_completion_bash hm status '')"
  assert_eq "" "$candidates" "status offers no argument"

  candidates="$(_completion_bash hm restore archive.tar.gz '')"
  assert_eq "" "$candidates" "restore offers nothing after its archive"

  candidates="$(_completion_bash hm gen --name '')"
  assert_eq "" "$candidates" "gen offers no value for --name"
}

test_completion_bash_offers_the_generation_ids() {
  local candidates

  _completion_fixture

  candidates="$(_completion_bash hm switch '' | tr '\n' ' ')"
  assert_eq "2 1 " "$candidates" "switch offers the ids, newest first"

  candidates="$(_completion_bash hm apply '' | tr '\n' ' ')"
  assert_eq "2 1 " "$candidates" "apply offers the ids, newest first"

  candidates="$(_completion_bash hm show '' | tr '\n' ' ')"
  assert_eq "2 1 " "$candidates" "show offers the ids, newest first"

  candidates="$(_completion_bash hm edit '' | tr '\n' ' ')"
  assert_eq "2 1 " "$candidates" "edit offers the ids, newest first"

  candidates="$(_completion_bash hm diff '' | tr '\n' ' ')"
  assert_eq "2 1 " "$candidates" "diff offers the ids, newest first"

  candidates="$(_completion_bash hm diff 1 '' | tr '\n' ' ')"
  assert_eq "2 1 " "$candidates" "diff keeps offering the ids after the first one"

  candidates="$(_completion_bash hm delete '' | tr '\n' ' ')"
  assert_eq "2 1 " "$candidates" "delete offers the ids, newest first"

  candidates="$(_completion_bash hm list --generation '' | tr '\n' ' ')"
  assert_eq "2 1 " "$candidates" "list --generation offers the ids, newest first"
}

test_completion_bash_offers_the_profile_names() {
  local candidates

  _completion_fixture
  printf 'third\n' > "$SRC_DIR/third.txt"
  run_hm_input 'y\n' add --profile nightly "$SRC_DIR/third.txt"
  assert_rc 0 "$HM_STATUS" "the fixture creates a second profile"

  candidates="$(_completion_bash hm gen --profile '' | tr '\n' ' ')"
  assert_eq "default nightly " "$candidates" \
    "gen --profile offers the profile names in order"

  candidates="$(_completion_bash hm list '--profile=' | tr '\n' ' ')"
  assert_eq "--profile=default --profile=nightly " "$candidates" \
    "the inline form offers the prefixed profile names"

  candidates="$(_completion_bash hm add "--profile=n" | tr '\n' ' ')"
  assert_eq "--profile=nightly " "$candidates" \
    "the inline form filters the profile names"
}

test_completion_bash_completes_the_inline_generation_option() {
  local candidates

  _completion_fixture

  candidates="$(_completion_bash hm list '--generation=' | tr '\n' ' ')"
  assert_eq "--generation=2 --generation=1 " "$candidates" \
    "the inline form offers the prefixed ids"

  candidates="$(_completion_bash hm list '--generation=2' | tr '\n' ' ')"
  assert_eq "--generation=2 " "$candidates" \
    "the inline form filters the ids with the typed value"
}

test_completion_bash_offers_the_tracked_paths() {
  local candidates

  _completion_fixture

  candidates="$(_completion_bash hm add "$SRC_DIR/")"
  assert_contains "$candidates" "$SRC_DIR/a.txt" "the tracked file is offered"
  assert_contains "$candidates" "$SRC_DIR/dir with space" "the tracked directory is offered"

  candidates="$(_completion_bash hm add "$SRC_DIR/s")"
  assert_contains "$candidates" "$SRC_DIR/second.txt" "the tracked path follows the prefix"
  assert_not_contains "$candidates" "$SRC_DIR/a.txt" "a path outside the prefix is not offered"
}

test_completion_bash_keeps_paths_with_spaces() {
  local candidates

  _completion_fixture

  candidates="$(_completion_bash hm add "$SRC_DIR/dir with space/")"
  assert_contains "$candidates" "$SRC_DIR/dir with space/b'q.txt" \
    "the path with a space and a quote is offered verbatim"

  candidates="$(_completion_bash hm add "$SRC_DIR/dir with space/b")"
  assert_contains "$candidates" "$SRC_DIR/dir with space/b'q.txt" \
    "the quote does not break the matching"
}

test_completion_bash_offers_the_backup_archives() {
  local candidates

  _completion_fixture

  run_hm backup
  assert_rc 0 "$HM_STATUS" "the fixture backup succeeded"

  candidates="$(_completion_bash hm restore "$HM_DIR/backup/")"
  assert_contains "$candidates" "hm-backup-" "the backup archive is offered"
}

test_completion_bash_fails_safe_without_a_database() {
  local candidates status

  _test_setup completion_without_database raw

  candidates="$(_completion_bash hm switch '')"
  status=$?

  assert_eq "0" "$status" "the completion succeeds without a database"
  assert_eq "" "$candidates" "no generation is offered without a database"
  assert_file_absent "$HM_DIR/db.sqlite" "the completion does not create a database"

  candidates="$(_completion_bash hm add '')"
  status=$?

  assert_eq "0" "$status" "the path completion succeeds without a database"
  assert_file_absent "$HM_DIR/db.sqlite" "the path completion does not create a database"

  printf 'not a database\n' > "$HM_DIR/db.sqlite"

  candidates="$(_completion_bash hm switch '')"
  status=$?

  assert_eq "0" "$status" "the completion succeeds with a broken database"
  assert_eq "" "$candidates" "no generation is offered from a broken database"
}

test_completion_bash_does_not_modify_the_project() {
  local before after

  _completion_fixture
  run_hm backup

  before="$(_completion_state)"

  _completion_bash hm '' > /dev/null
  _completion_bash hm gen '--' > /dev/null
  _completion_bash hm switch '' > /dev/null
  _completion_bash hm show '' > /dev/null
  _completion_bash hm edit '' > /dev/null
  _completion_bash hm diff '' > /dev/null
  _completion_bash hm status '' > /dev/null
  _completion_bash hm delete '' > /dev/null
  _completion_bash hm add "$SRC_DIR/" > /dev/null
  _completion_bash hm restore '' > /dev/null
  _completion_bash hm list '--generation=' > /dev/null

  after="$(_completion_state)"

  assert_eq "$before" "$after" "the completion leaves the project untouched"
  assert_file_absent "$HM_DIR/db.sqlite-wal" "no write-ahead log is created"
  assert_file_absent "$HM_DIR/db.sqlite-shm" "no shared memory file is created"
  assert_file_absent "$HM_DIR/db.sqlite-journal" "no rollback journal is created"
}

# --- The fish completion ---------------------------------------------------

test_completion_fish_offers_the_commands() {
  local candidates

  if ! _completion_fish_available; then
    printf '      SKIP fish is not installed, the fish completion was not executed.\n' >&2
    return 0
  fi

  _test_setup completion_fish_commands

  candidates="$(_completion_fish 'hm ')"

  assert_contains "$candidates" "init" "the fish completion offers init"
  assert_contains "$candidates" "add" "the fish completion offers add"
  assert_contains "$candidates" "gen" "the fish completion offers gen"
  assert_contains "$candidates" "list" "the fish completion offers list"
  assert_contains "$candidates" "status" "the fish completion offers status"
  assert_contains "$candidates" "show" "the fish completion offers show"
  assert_contains "$candidates" "edit" "the fish completion offers edit"
  assert_contains "$candidates" "diff" "the fish completion offers diff"
  assert_contains "$candidates" "switch" "the fish completion offers switch"
  assert_contains "$candidates" "delete" "the fish completion offers delete"
  assert_contains "$candidates" "apply" "the fish completion offers apply"
  assert_contains "$candidates" "discard" "the fish completion offers discard"
  assert_contains "$candidates" "backup" "the fish completion offers backup"
  assert_contains "$candidates" "restore" "the fish completion offers restore"
  assert_contains "$candidates" "clean" "the fish completion offers clean"
  assert_contains "$candidates" "help" "the fish completion offers help"
  assert_not_contains "$candidates" "install" "the fish completion offers no phantom command"
}

test_completion_fish_offers_the_options_of_each_command() {
  local candidates

  if ! _completion_fish_available; then
    printf '      SKIP fish is not installed, the fish completion was not executed.\n' >&2
    return 0
  fi

  _test_setup completion_fish_options

  candidates="$(_completion_fish 'hm gen --')"
  assert_contains "$candidates" "--name" "the fish completion offers --name"
  assert_contains "$candidates" "--comment" "the fish completion offers --comment"
  assert_contains "$candidates" "--yes" "the fish completion offers --yes"

  candidates="$(_completion_fish 'hm list --')"
  assert_contains "$candidates" "--generation" "the fish completion offers --generation"
  assert_contains "$candidates" "--pending" "the fish completion offers --pending"
  assert_contains "$candidates" "--paths" "the fish completion offers --paths"
  assert_contains "$candidates" "--store" "the fish completion offers --store"

  candidates="$(_completion_fish 'hm backup --')"
  assert_contains "$candidates" "--help" "the fish completion offers --help for backup"
  assert_not_contains "$candidates" "--yes" "the fish completion does not offer --yes for backup"

  candidates="$(_completion_fish 'hm delete --')"
  assert_contains "$candidates" "--yes" "the fish completion offers --yes for delete"

  candidates="$(_completion_fish 'hm show --')"
  assert_contains "$candidates" "--help" "the fish completion offers --help for show"
  assert_not_contains "$candidates" "--yes" "the fish completion does not offer --yes for show"

  candidates="$(_completion_fish 'hm status --')"
  assert_contains "$candidates" "--help" "the fish completion offers --help for status"
  assert_not_contains "$candidates" "--yes" "the fish completion does not offer --yes for status"

  candidates="$(_completion_fish 'hm edit --')"
  assert_contains "$candidates" "--name" "the fish completion offers --name for edit"
  assert_contains "$candidates" "--comment" "the fish completion offers --comment for edit"
  assert_contains "$candidates" "--clear-name" "the fish completion offers --clear-name for edit"
  assert_contains "$candidates" "--clear-comment" "the fish completion offers --clear-comment for edit"
  assert_contains "$candidates" "--yes" "the fish completion offers --yes for edit"

  candidates="$(_completion_fish 'hm diff --')"
  assert_contains "$candidates" "--all" "the fish completion offers --all for diff"
  assert_not_contains "$candidates" "--yes" "the fish completion does not offer --yes for diff"
}

test_completion_fish_offers_the_generation_ids() {
  local candidates

  if ! _completion_fish_available; then
    printf '      SKIP fish is not installed, the fish completion was not executed.\n' >&2
    return 0
  fi

  _completion_fixture
  run_hm backup

  candidates="$(_completion_fish 'hm switch ')"
  assert_contains "$candidates" "2" "the fish completion offers the newest generation"
  assert_contains "$candidates" "1" "the fish completion offers the older generation"

  candidates="$(_completion_fish 'hm apply --dry-run ')"
  assert_contains "$candidates" "2" "the fish completion offers the ids after an option"

  candidates="$(_completion_fish 'hm show ')"
  assert_contains "$candidates" "2" "the fish completion offers the ids for show"

  candidates="$(_completion_fish 'hm edit ')"
  assert_contains "$candidates" "2" "the fish completion offers the ids for edit"

  candidates="$(_completion_fish 'hm diff ')"
  assert_contains "$candidates" "2" "the fish completion offers the ids for diff"

  candidates="$(_completion_fish 'hm diff 1 ')"
  assert_contains "$candidates" "2" "the fish completion offers the ids after the first one"

  candidates="$(_completion_fish 'hm delete ')"
  assert_contains "$candidates" "2" "the fish completion offers the ids for delete"

  candidates="$(_completion_fish 'hm restore --yes ')"
  assert_contains "$candidates" "hm-backup-" "the fish completion offers the archives after an option"

  candidates="$(_completion_fish 'hm list --generation=')"
  assert_contains "$candidates" "--generation=2" "the fish completion offers the inline form"
}

test_completion_fish_does_not_offer_arguments_out_of_range() {
  local candidates

  if ! _completion_fish_available; then
    printf '      SKIP fish is not installed, the fish completion was not executed.\n' >&2
    return 0
  fi

  _completion_fixture

  candidates="$(_completion_fish 'hm switch 1 ')"
  assert_eq "" "$candidates" "fish offers nothing after the generation of switch"

  candidates="$(_completion_fish 'hm apply 1 ')"
  assert_eq "" "$candidates" "fish offers nothing after the generation of apply"

  candidates="$(_completion_fish 'hm delete 1 ')"
  assert_eq "" "$candidates" "fish offers nothing after the generation of delete"

  candidates="$(_completion_fish 'hm apply --dry-run 1 ')"
  assert_eq "" "$candidates" "fish offers nothing after the generation following an option"

  candidates="$(_completion_fish 'hm init ')"
  assert_eq "" "$candidates" "fish offers no argument for init"

  candidates="$(_completion_fish 'hm status ')"
  assert_eq "" "$candidates" "fish offers no argument for status"

  candidates="$(_completion_fish 'hm edit 1 ')"
  assert_eq "" "$candidates" "fish offers nothing after the generation of edit"

  candidates="$(_completion_fish 'hm gen --name ')"
  assert_eq "" "$candidates" "fish offers no value for --name"
}

# --- The zsh completion ----------------------------------------------------

test_completion_zsh_syntax() {
  local root

  if ! _completion_zsh_available; then
    printf '      SKIP zsh is not installed, the zsh completion was not executed.\n' >&2
    return 0
  fi

  root="$(_completion_root)"

  if ! zsh -n "$root/completions/hm.zsh"; then
    _test_fail "the zsh completion does not parse"
    return 1
  fi

  _test_ok "the zsh completion parses"
}

test_completion_zsh_registers_the_completion() {
  local root registered

  if ! _completion_zsh_available; then
    printf '      SKIP zsh is not installed, the zsh completion was not executed.\n' >&2
    return 0
  fi

  root="$(_completion_root)"
  _test_setup completion_zsh

  registered="$(
    HOME="$TEST_DIR" zsh -f -c '
      autoload -Uz compinit
      compinit -u -d "$1/zcompdump"
      source "$2/completions/hm.zsh"
      print -r -- "${_comps[hm]}"
    ' zsh "$TEST_DIR" "$root"
  )"

  assert_eq "_hm" "$registered" "the zsh completion registers itself for hm"
}
