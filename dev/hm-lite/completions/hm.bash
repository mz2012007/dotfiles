#!/usr/bin/env bash
#
# completions/hm.bash - bash completion for HM-Lite.
#
# The file is self contained. It only uses bash builtins and it never runs
# the hm executable, therefore completing a command line can never change
# the state of a project.
#
# Enable it for the current session with:
#
#   source /path/to/hm-lite/completions/hm.bash
#
# The completion never fails the shell. When the project database cannot be
# read, the dynamic suggestions are simply not offered.
#
# Requirements: bash 4.4 or newer, the sqlite3 command line tool.

# ---------------------------------------------------------------------------
# The state of the project
# ---------------------------------------------------------------------------

# _hm_runtime_dir
# Print the runtime directory of the project. The resolution matches the hm
# executable: the environment wins, the default is ~/.config/hm-lite.
_hm_runtime_dir() {
  if [[ -n "${HM_DIR:-}" ]]; then
    printf '%s\n' "$HM_DIR"
    return 0
  fi

  if [[ -z "${HOME:-}" ]]; then
    return 1
  fi

  printf '%s\n' "$HOME/.config/hm-lite"
}

# _hm_db_file
# Print the path of the project database.
_hm_db_file() {
  if [[ -n "${HM_DB_FILE:-}" ]]; then
    printf '%s\n' "$HM_DB_FILE"
    return 0
  fi

  local dir
  dir="$(_hm_runtime_dir)" || return 1

  printf '%s\n' "$dir/db.sqlite"
}

# _hm_generation_ids
# Print the identifiers of the known generations, newest first. A missing or
# unreadable database is not an error, it produces no output. The database is
# opened read only, the file is never created and never modified.
_hm_generation_ids() {
  local db
  db="$(_hm_db_file)" || return 0
  [[ -f "$db" ]] || return 0

  sqlite3 -readonly -noheader -list "$db" \
    'SELECT id FROM generations ORDER BY created_at DESC, id DESC;' 2>/dev/null || true
}

# _hm_profile_names
# Print the names of the profiles, in name order. A missing or unreadable
# database is not an error, it produces no output.
_hm_profile_names() {
  local db
  db="$(_hm_db_file)" || return 0
  [[ -f "$db" ]] || return 0

  sqlite3 -readonly -noheader -list "$db" \
    'SELECT name FROM profiles ORDER BY name;' 2>/dev/null || true
}

# _hm_tracked_paths
# Print the paths that the project already tracks. The database is opened
# read only, the file is never created and never modified.
_hm_tracked_paths() {
  local db
  db="$(_hm_db_file)" || return 0
  [[ -f "$db" ]] || return 0

  sqlite3 -readonly -noheader -list "$db" \
    'SELECT path FROM paths ORDER BY path;' 2>/dev/null || true
}

# _hm_backup_archives
# Print the backup archives that the project owns.
_hm_backup_archives() {
  local dir archive
  local -a archives=()

  dir="$(_hm_runtime_dir)" || return 0
  [[ -d "$dir/backup" ]] || return 0

  for archive in "$dir"/backup/hm-backup-*.tar.gz; do
    [[ -f "$archive" ]] || continue
    archives+=("$archive")
  done

  (( ${#archives[@]} > 0 )) || return 0
  printf '%s\n' "${archives[@]}"
}

# ---------------------------------------------------------------------------
# The command surface
# ---------------------------------------------------------------------------

# _hm_command_names
# Print the commands of the application, one per line.
_hm_command_names() {
  printf '%s\n' init profile add gen list status show diff edit switch delete apply discard backup restore clean help
}

# _hm_global_options
# Print the global options of the application, one per line.
_hm_global_options() {
  printf '%s\n' --help -h --version
}

# _hm_profile_subcommands
# Print the subcommands of "hm profile", one per line.
_hm_profile_subcommands() {
  printf '%s\n' add list show use rename delete help
}

# _hm_command_options COMMAND
# Print the options that the command supports, one per line. An option that
# consumes the word that follows it is marked with a trailing "=".
_hm_command_options() {
  case "$1" in
    init)
      printf '%s\n' -h --help
      ;;
    add)
      printf '%s\n' --profile= -h --help
      ;;
    profile)
      printf '%s\n' -h --help
      ;;
    gen)
      printf '%s\n' --profile= --name= --comment= --yes -y -h --help
      ;;
    list)
      printf '%s\n' --profile= --generation= --pending --paths --store -h --help
      ;;
    status)
      printf '%s\n' --profile= -h --help
      ;;
    show)
      printf '%s\n' --profile= -h --help
      ;;
    diff)
      printf '%s\n' --profile= --all -h --help
      ;;
    edit)
      printf '%s\n' --profile= --name= --comment= --clear-name --clear-comment --yes -y -h --help
      ;;
    switch)
      printf '%s\n' --profile= -h --help
      ;;
    delete)
      printf '%s\n' --profile= --yes -y -h --help
      ;;
    apply)
      printf '%s\n' --profile= --dry-run --yes -y -h --help
      ;;
    discard)
      printf '%s\n' -h --help
      ;;
    backup)
      printf '%s\n' -h --help
      ;;
    restore)
      printf '%s\n' --yes -y -h --help
      ;;
    clean)
      printf '%s\n' --dry-run --yes -y -h --help
      ;;
    *)
      return 1
      ;;
  esac
}

# ---------------------------------------------------------------------------
# The completion itself
# ---------------------------------------------------------------------------

# _hm_is_value_option COMMAND OPTION
# Return 0 when the option consumes the word that follows it.
_hm_is_value_option() {
  local command="$1" option="$2"
  local -a entries=()
  local entry

  mapfile -t entries < <(_hm_command_options "$command")

  for entry in "${entries[@]}"; do
    if [[ "$entry" == "$option=" ]]; then
      return 0
    fi
  done

  return 1
}

# _hm_complete_command CURRENT
# Complete the name of a command.
_hm_complete_command() {
  local current="$1"
  local -a names=()
  local name

  mapfile -t names < <(_hm_command_names)

  for name in "${names[@]}"; do
    if [[ "$name" == "$current"* ]]; then
      COMPREPLY+=("$name")
    fi
  done

  mapfile -t names < <(_hm_global_options)

  for name in "${names[@]}"; do
    if [[ "$name" == "$current"* ]]; then
      COMPREPLY+=("$name")
    fi
  done
}

# _hm_complete_option COMMAND CURRENT [POSITIONALS...]
# Complete the options of a command. A leading profile subcommand narrows
# the options of "hm profile" to the ones that the subcommand supports.
_hm_complete_option() {
  local command="$1" current="$2"
  shift 2
  local profile_subcommand="${1:-}"
  local -a entries=()
  local entry

  case "$command:$profile_subcommand" in
    profile:delete)
      entries=(--force --yes -y -h --help)
      ;;
    profile:rename)
      entries=(--yes -y -h --help)
      ;;
    *)
      mapfile -t entries < <(_hm_command_options "$command")
      ;;
  esac

  for entry in "${entries[@]}"; do
    entry="${entry%=}"
    if [[ "$entry" == "$current"* ]]; then
      COMPREPLY+=("$entry")
    fi
  done
}

# _hm_complete_generation CURRENT PREFIX
# Complete the identifier of a generation. PREFIX is prepended to every
# candidate, it carries the "--option=" prefix of the inline form.
_hm_complete_generation() {
  local current="$1" prefix="$2"
  local -a ids=()
  local id

  mapfile -t ids < <(_hm_generation_ids)

  for id in "${ids[@]}"; do
    if [[ "$id" == "$current"* ]]; then
      COMPREPLY+=("$prefix$id")
    fi
  done
}

# _hm_complete_profile CURRENT PREFIX
# Complete the name of a profile. PREFIX is prepended to every candidate, it
# carries the "--option=" prefix of the inline form.
_hm_complete_profile() {
  local current="$1" prefix="$2"
  local -a names=()
  local name

  mapfile -t names < <(_hm_profile_names)

  for name in "${names[@]}"; do
    if [[ "$name" == "$current"* ]]; then
      COMPREPLY+=("$prefix$name")
    fi
  done
}

# _hm_complete_path CURRENT
# Complete the paths of the filesystem and the paths that the project already
# tracks.
_hm_complete_path() {
  local current="$1"
  local -a tracked=()
  local -a files=()
  local -A seen=()
  local path

  mapfile -t tracked < <(_hm_tracked_paths)
  mapfile -t files < <(compgen -f -- "$current")

  for path in "${tracked[@]}"; do
    if [[ -n "$path" && "$path" == "$current"* && -z "${seen["$path"]+x}" ]]; then
      seen["$path"]=1
      COMPREPLY+=("$path")
    fi
  done

  for path in "${files[@]}"; do
    if [[ -n "$path" && -z "${seen["$path"]+x}" ]]; then
      seen["$path"]=1
      COMPREPLY+=("$path")
    fi
  done
}

# _hm_complete_archive CURRENT
# Complete the backup archives of the project and the files of the filesystem.
_hm_complete_archive() {
  local current="$1"
  local -a archives=()
  local -a files=()
  local archive

  mapfile -t archives < <(_hm_backup_archives)
  mapfile -t files < <(compgen -f -- "$current")

  for archive in "${archives[@]}"; do
    if [[ "$archive" == "$current"* ]]; then
      COMPREPLY+=("$archive")
    fi
  done

  if (( ${#files[@]} > 0 )); then
    COMPREPLY+=("${files[@]}")
  fi
}

# _hm_complete_argument COMMAND COUNT CURRENT [POSITIONALS...]
# Complete the argument of a command. COUNT is the number of arguments that
# the command already received, POSITIONALS carries their values.
_hm_complete_argument() {
  local command="$1" count="$2" current="$3"
  shift 3
  local -a positionals=("$@")
  local -a names=()
  local name

  case "$command" in
    add)
      _hm_complete_path "$current"
      ;;
    profile)
      if (( count == 0 )); then
        mapfile -t names < <(_hm_profile_subcommands)
        for name in "${names[@]}"; do
          if [[ "$name" == "$current"* ]]; then
            COMPREPLY+=("$name")
          fi
        done
      else
        case "${positionals[0]}" in
          show | use | delete)
            if (( count == 1 )); then
              _hm_complete_profile "$current" ""
            fi
            ;;
          rename)
            if (( count == 1 || count == 2 )); then
              _hm_complete_profile "$current" ""
            fi
            ;;
          add)
            if (( count >= 2 )); then
              _hm_complete_path "$current"
            fi
            ;;
        esac
      fi
      ;;
    switch)
      if (( count == 0 )); then
        _hm_complete_generation "$current" ""
      fi
      ;;
    show)
      if (( count == 0 )); then
        _hm_complete_generation "$current" ""
      fi
      ;;
    diff)
      _hm_complete_generation "$current" ""
      ;;
    edit)
      if (( count == 0 )); then
        _hm_complete_generation "$current" ""
      fi
      ;;
    delete)
      if (( count == 0 )); then
        _hm_complete_generation "$current" ""
      fi
      ;;
    apply)
      if (( count == 0 )); then
        _hm_complete_generation "$current" ""
      fi
      ;;
    restore)
      if (( count == 0 )); then
        _hm_complete_archive "$current"
      fi
      ;;
    *)
      ;;
  esac

  return 0
}

# _hm - the completion function of the hm command.
_hm() {
  local current command command_index index word prefix value
  local pending_option=""
  local -a positionals=()
  local -a words=()

  COMPREPLY=()

  if (( ${#COMP_WORDS[@]} > 0 )); then
    words=("${COMP_WORDS[@]}")
  fi

  local cword="${COMP_CWORD:-0}"
  (( cword < ${#words[@]} )) || cword=$(( ${#words[@]} - 1 ))
  current="${words[cword]-}"

  command=""
  command_index=0

  # The command is the first word that is not an option. The global options
  # end the command line, nothing follows them.
  for (( index = 1; index < cword; index++ )); do
    word="${words[index]}"
    case "$word" in
      -h | --help | --version)
        return 0
        ;;
      -*)
        continue
        ;;
      *)
        command="$word"
        command_index="$index"
        break
        ;;
    esac
  done

  if [[ -z "$command" ]]; then
    _hm_complete_command "$current"
    return 0
  fi

  # Collect the words that follow the command.
  index=$(( command_index + 1 ))
  while (( index < cword )); do
    word="${words[index]}"
    case "$word" in
      --*=*)
        # An option with an inline value, it consumes nothing else.
        pending_option=""
        ;;
      -*)
        if _hm_is_value_option "$command" "$word"; then
          pending_option="$word"
        else
          pending_option=""
        fi
        ;;
      *)
        if [[ -n "$pending_option" ]]; then
          pending_option=""
        else
          positionals+=("$word")
        fi
        ;;
    esac
    index=$(( index + 1 ))
  done

  # The previous word waits for its value.
  if [[ -n "$pending_option" ]]; then
    case "$pending_option" in
      --generation) _hm_complete_generation "$current" "" ;;
      --profile) _hm_complete_profile "$current" "" ;;
    esac
    return 0
  fi

  # The current word carries an inline value, for example "--generation=3".
  if [[ "$current" == *=* ]]; then
    prefix="${current%=*}"
    value="${current#*=}"
    if _hm_is_value_option "$command" "$prefix"; then
      case "$prefix" in
        --generation) _hm_complete_generation "$value" "$prefix=" ;;
        --profile) _hm_complete_profile "$value" "$prefix=" ;;
      esac
      return 0
    fi
  fi

  # The current word is an option.
  if [[ "$current" == -* ]]; then
    _hm_complete_option "$command" "$current" "${positionals[@]}"
    return 0
  fi

  # The current word is an argument of the command.
  _hm_complete_argument "$command" "${#positionals[@]}" "$current" "${positionals[@]}"
  return 0
}

complete -o filenames -F _hm hm
