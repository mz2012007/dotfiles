#compdef hm
#
# completions/hm.zsh - zsh completion for HM-Lite.
#
# The file is self contained. It only uses the completion system of zsh and
# it never runs the hm executable, therefore completing a command line can
# never change the state of a project.
#
# Enable it in one of the two ways:
#
#   source /path/to/hm-lite/completions/hm.zsh
#
# or install it under the name "_hm" in a directory that is part of $fpath:
#
#   cp hm.zsh ~/.zsh/completions/_hm
#   fpath=(~/.zsh/completions $fpath)
#   autoload -Uz compinit && compinit
#
# The completion never fails the shell. When the project database cannot be
# read, the dynamic suggestions are simply not offered. The file requires
# an initialized completion system and the sqlite3 command line tool.

# ---------------------------------------------------------------------------
# The state of the project
# ---------------------------------------------------------------------------

# __hm_runtime_dir
# Print the runtime directory of the project. The resolution matches the hm
# executable: the environment wins, the default is ~/.config/hm-lite.
__hm_runtime_dir() {
  if [[ -n ${HM_DIR:-} ]]; then
    print -r -- $HM_DIR
    return 0
  fi

  if [[ -z ${HOME:-} ]]; then
    return 1
  fi

  print -r -- $HOME/.config/hm-lite
}

# __hm_db_file
# Print the path of the project database.
__hm_db_file() {
  if [[ -n ${HM_DB_FILE:-} ]]; then
    print -r -- $HM_DB_FILE
    return 0
  fi

  local dir
  dir=$(__hm_runtime_dir) || return 1

  print -r -- $dir/db.sqlite
}

# __hm_context_profile
# Print the profile that scopes the current command line: an explicit
# --profile wins, then HM_PROFILE, the active profile and the default
# profile.
__hm_context_profile() {
  local selected="${HM_PROFILE:-}" active="" db
  local current=${CURRENT:-0}
  local i word

  for (( i = 2; i < current; i++ )); do
    word=${words[i]-}
    case $word in
      --profile)
        (( i + 1 < current )) && selected=${words[i + 1]-}
        ;;
      --profile=*)
        selected=${word#--profile=}
        ;;
    esac
  done

  if [[ -n $selected ]]; then
    print -r -- $selected
    return 0
  fi

  db=$(__hm_db_file) || true
  if [[ -n $db && -f $db ]]; then
    active=$(sqlite3 -readonly -noheader -list $db \
      "SELECT value FROM state WHERE key = 'active_profile';" 2>/dev/null)
  fi

  print -r -- ${active:-default}
}

# __hm_generation_ids
# Print the local generation numbers of the effective profile, newest first.
# A missing or unreadable database is not an error, it produces no output.
# The database is opened read only, the file is never created and never
# modified.
__hm_generation_ids() {
  local db profile row name number
  db=$(__hm_db_file) || return 0
  [[ -f $db ]] || return 0

  profile=$(__hm_context_profile)

  for row in "${(@f)$(sqlite3 -readonly -noheader -list $db \
      'SELECT pr.name || char(9) || g.number
         FROM generations g
         JOIN profiles pr ON pr.id = g.profile_id
        ORDER BY g.created_at DESC, g.id DESC;' 2>/dev/null)}"; do
    [[ -n $row ]] || continue
    name=${row%%$'\t'*}
    number=${row#*$'\t'}
    [[ $name == $profile ]] && print -r -- $number
  done
}

# __hm_profile_names
# Print the names of the profiles, in name order. A missing or unreadable
# database is not an error, it produces no output.
__hm_profile_names() {
  local db
  db=$(__hm_db_file) || return 0
  [[ -f $db ]] || return 0

  sqlite3 -readonly -noheader -list $db \
    'SELECT name FROM profiles ORDER BY name;' 2>/dev/null
}

# __hm_tracked_paths
# Print the paths that the project already tracks. The database is opened
# read only, the file is never created and never modified.
__hm_tracked_paths() {
  local db
  db=$(__hm_db_file) || return 0
  [[ -f $db ]] || return 0

  sqlite3 -readonly -noheader -list $db \
    'SELECT path FROM paths ORDER BY path;' 2>/dev/null
}

# __hm_backup_archives
# Print the backup archives that the project owns.
__hm_backup_archives() {
  local dir archive
  local -a archives

  dir=$(__hm_runtime_dir) || return 0
  [[ -d $dir/backup ]] || return 0

  for archive in $dir/backup/hm-backup-*.tar.gz(N); do
    archives+=($archive)
  done

  (( ${#archives} )) || return 0
  print -l -- $archives
}

# ---------------------------------------------------------------------------
# The command surface
# ---------------------------------------------------------------------------

# _hm_is_value_option SUBCOMMAND OPTION
# Return 0 when the option consumes the word that follows it.
_hm_is_value_option() {
  case $1:$2 in
    gen:--name | gen:--comment | gen:--profile)
      return 0
      ;;
    list:--generation | list:--profile)
      return 0
      ;;
    add:--profile | status:--profile | apply:--profile | discard:--profile)
      return 0
      ;;
    show:--profile | diff:--profile | switch:--profile | delete:--profile)
      return 0
      ;;
    edit:--name | edit:--comment | edit:--profile)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

# _hm_commands
# Complete the name of a command and the global options.
_hm_commands() {
  local -a commands global
  commands=(
    'init:Initialize the HM-Lite project directory'
    'profile:Manage profiles and the active context'
    'add:Register paths for the next generation'
    'gen:Create a generation from the pending paths'
    'list:Show generations, entries and pending paths'
    'status:Show the project, the content store and every generation'
    'show:Show the metadata and the entries of a generation'
    'diff:Compare the entries of two or more generations'
    'edit:Change the name and the comment of a generation'
    'switch:Select a generation and materialize it in current/'
    'delete:Delete a generation that is not selected'
    'apply:Apply a generation to the tracked live paths'
    'discard:Reset the testing workspace from current/'
    'backup:Create a consistent backup of the project state'
    'restore:Restore a previously created backup'
    'clean:Remove the unreferenced content objects'
    'help:Show the usage of HM-Lite'
  )
  global=(
    '-h:Show the usage of HM-Lite'
    '--help:Show the usage of HM-Lite'
    '--version:Show the version of HM-Lite'
  )

  _describe -t commands 'hm command' commands
  _describe -t options 'global option' global
}

# _hm_options SUBCOMMAND [POSITIONALS...]
# Complete the options of a subcommand. A leading profile subcommand narrows
# the options of "hm profile" to the ones that the subcommand supports.
_hm_options() {
  local -a options
  local profile_subcommand="${2:-}"

  case $1 in
    init | backup)
      options=(
        '-h:Show the usage of the command'
        '--help:Show the usage of the command'
      )
      ;;
    discard)
      options=(
        '--profile:Profile of the current tree'
        '-h:Show the usage of the command'
        '--help:Show the usage of the command'
      )
      ;;
    profile)
      case $profile_subcommand in
        delete)
          options=(
            '--force:Delete the history as well'
            '--yes:Do not ask for a confirmation'
            '-y:Do not ask for a confirmation'
            '-h:Show the usage of the command'
            '--help:Show the usage of the command'
          )
          ;;
        rename)
          options=(
            '--yes:Do not ask for a confirmation'
            '-y:Do not ask for a confirmation'
            '-h:Show the usage of the command'
            '--help:Show the usage of the command'
          )
          ;;
        *)
          options=(
            '-h:Show the usage of the command'
            '--help:Show the usage of the command'
          )
          ;;
      esac
      ;;
    show | switch)
      options=(
        '--profile:Profile to use'
        '-h:Show the usage of the command'
        '--help:Show the usage of the command'
      )
      ;;
    add | status)
      options=(
        '--profile:Profile to use'
        '-h:Show the usage of the command'
        '--help:Show the usage of the command'
      )
      ;;
    diff)
      options=(
        '--profile:Profile to use'
        '--all:Show the entries that did not change'
        '-h:Show the usage of the command'
        '--help:Show the usage of the command'
      )
      ;;
    edit)
      options=(
        '--profile:Profile to use'
        '--name:Name of the generation'
        '--comment:Comment of the generation'
        '--clear-name:Remove the name of the generation'
        '--clear-comment:Remove the comment of the generation'
        '--yes:Do not ask for a confirmation'
        '-y:Do not ask for a confirmation'
        '-h:Show the usage of the command'
        '--help:Show the usage of the command'
      )
      ;;
    gen)
      options=(
        '--profile:Profile to use'
        '--name:Name of the generation'
        '--comment:Comment of the generation'
        '--yes:Do not ask for a confirmation'
        '-y:Do not ask for a confirmation'
        '-h:Show the usage of the command'
        '--help:Show the usage of the command'
      )
      ;;
    list)
      options=(
        '--profile:Profile to show'
        '--generation:Identifier of the generation'
        '--pending:Show the paths that are queued for the next generation'
        '--paths:Show the tracked paths'
        '--store:Show the statistics of the content store'
        '-h:Show the usage of the command'
        '--help:Show the usage of the command'
      )
      ;;
    apply)
      options=(
        '--profile:Profile of the selection'
        '--dry-run:Show what would be changed'
        '--yes:Do not ask for a confirmation'
        '-y:Do not ask for a confirmation'
        '-h:Show the usage of the command'
        '--help:Show the usage of the command'
      )
      ;;
    clean)
      options=(
        '--dry-run:Show what would be changed'
        '--yes:Do not ask for a confirmation'
        '-y:Do not ask for a confirmation'
        '-h:Show the usage of the command'
        '--help:Show the usage of the command'
      )
      ;;
    restore)
      options=(
        '--yes:Do not ask for a confirmation'
        '-y:Do not ask for a confirmation'
        '-h:Show the usage of the command'
        '--help:Show the usage of the command'
      )
      ;;
    delete)
      options=(
        '--profile:Profile to use'
        '--yes:Do not ask for a confirmation'
        '-y:Do not ask for a confirmation'
        '-h:Show the usage of the command'
        '--help:Show the usage of the command'
      )
      ;;
    *)
      return 0
      ;;
  esac

  _describe -t options 'option' options
}

# _hm_value OPTION
# Complete the value of an option.
_hm_value() {
  local -a ids

  case $1 in
    --generation)
      ids=(${(f)"$(__hm_generation_ids)"})
      ids=(${ids:#})
      (( ${#ids} )) && compadd -- $ids
      ;;
    --profile)
      ids=(${(f)"$(__hm_profile_names)"})
      ids=(${ids:#})
      (( ${#ids} )) && compadd -- $ids
      ;;
    *)
      return 0
      ;;
  esac
}

# _hm_argument SUBCOMMAND COUNT [POSITIONALS...]
# Complete the argument of a subcommand. COUNT is the number of arguments
# that the subcommand already received, POSITIONALS carries their values.
_hm_argument() {
  local -a candidates
  local -a subcommands

  case $1 in
    profile)
      if (( $2 == 0 )); then
        subcommands=(
          'create:Create a profile with a root directory'
          'add:Create a legacy profile and optionally register paths'
          'list:List the profiles and their counts'
          'show:Show the paths and generations of a profile'
          'use:Select the active profile, or print it'
          'rename:Rename a profile and its context'
          'delete:Delete a profile after a confirmation'
          'help:Show the usage of the profile command'
        )
        _describe -t profile-subcommands 'profile subcommand' subcommands
        return 0
      fi

      case ${3:-} in
        show | use | delete)
          if (( $2 == 1 )); then
            _hm_value --profile
          fi
          ;;
        rename)
          if (( $2 == 1 || $2 == 2 )); then
            _hm_value --profile
          fi
          ;;
        create)
          if (( $2 == 2 )); then
            _directories
          fi
          ;;
        add)
          if (( $2 >= 2 )); then
            candidates=(${(f)"$(__hm_tracked_paths)"})
            candidates=(${candidates:#})
            (( ${#candidates} )) && compadd -- $candidates
            _files
          fi
          ;;
      esac
      return 0
      ;;
    add)
      candidates=(${(f)"$(__hm_tracked_paths)"})
      candidates=(${candidates:#})
      (( ${#candidates} )) && compadd -- $candidates
      _files
      ;;
    switch | apply | show | delete)
      if (( $2 == 0 )); then
        _hm_value --generation
      fi
      ;;
    edit)
      if (( $2 == 0 )); then
        _hm_value --generation
      fi
      ;;
    diff)
      _hm_value --generation
      ;;
    restore)
      if (( $2 == 0 )); then
        candidates=(${(f)"$(__hm_backup_archives)"})
        candidates=(${candidates:#})
        (( ${#candidates} )) && compadd -- $candidates
        _files
      fi
      ;;
    *)
      ;;
  esac

  return 0
}

# _hm - the completion function of the hm command.
_hm() {
  local i word subcommand="" subcommand_index=0
  local pending="" prefix=""
  local -a positionals

  # The subcommand is the first word that is not an option. The global
  # options end the command line, nothing follows them.
  for (( i = 2; i < CURRENT; i++ )); do
    word=${words[i]}
    case $word in
      -h | --help | --version)
        return 0
        ;;
      -*)
        continue
        ;;
      *)
        subcommand=$word
        subcommand_index=$i
        break
        ;;
    esac
  done

  if [[ -z $subcommand ]]; then
    _hm_commands
    return 0
  fi

  # Collect the words that follow the subcommand.
  for (( i = subcommand_index + 1; i < CURRENT; i++ )); do
    word=${words[i]}
    case $word in
      --*=*)
        # An option with an inline value, it consumes nothing else.
        pending=""
        ;;
      -*)
        if _hm_is_value_option $subcommand $word; then
          pending=$word
        else
          pending=""
        fi
        ;;
      *)
        if [[ -n $pending ]]; then
          pending=""
        else
          positionals+=($word)
        fi
        ;;
    esac
  done

  # The previous word waits for its value.
  if [[ -n $pending ]]; then
    _hm_value $pending
    return 0
  fi

  # The current word carries an inline value, for example "--generation=3".
  if [[ $PREFIX == *=* ]]; then
    prefix=${PREFIX%%=*}
    if _hm_is_value_option $subcommand $prefix; then
      compset -P '*='
      _hm_value $prefix
      return 0
    fi
  fi

  # The current word is an option.
  if [[ $PREFIX == -* ]]; then
    _hm_options $subcommand "${positionals[@]}"
    return 0
  fi

  # The current word is an argument of the subcommand.
  _hm_argument $subcommand ${#positionals} "${positionals[@]}"
  return 0
}

# ---------------------------------------------------------------------------
# Registration
# ---------------------------------------------------------------------------

# The completion system has to be initialized first.
if (( $+functions[compdef] )); then
  compdef _hm hm
fi
