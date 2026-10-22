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

# __hm_generation_ids
# Print the identifiers of the known generations, newest first. A missing or
# unreadable database is not an error, it produces no output. The database is
# opened read only, the file is never created and never modified.
__hm_generation_ids() {
  local db
  db=$(__hm_db_file) || return 0
  [[ -f $db ]] || return 0

  sqlite3 -readonly -noheader -list $db \
    'SELECT id FROM generations ORDER BY created_at DESC, id DESC;' 2>/dev/null
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
    gen:--name | gen:--comment | list:--generation)
      return 0
      ;;
    edit:--name | edit:--comment)
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

# _hm_options SUBCOMMAND
# Complete the options of a subcommand.
_hm_options() {
  local -a options

  case $1 in
    init | add | status | show | switch | discard | backup)
      options=(
        '-h:Show the usage of the command'
        '--help:Show the usage of the command'
      )
      ;;
    diff)
      options=(
        '--all:Show the entries that did not change'
        '-h:Show the usage of the command'
        '--help:Show the usage of the command'
      )
      ;;
    edit)
      options=(
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
        '--generation:Identifier of the generation'
        '--pending:Show the paths that are queued for the next generation'
        '--paths:Show the tracked paths'
        '--store:Show the statistics of the content store'
        '-h:Show the usage of the command'
        '--help:Show the usage of the command'
      )
      ;;
    apply | clean)
      options=(
        '--dry-run:Show what would be changed'
        '--yes:Do not ask for a confirmation'
        '-y:Do not ask for a confirmation'
        '-h:Show the usage of the command'
        '--help:Show the usage of the command'
      )
      ;;
    restore | delete)
      options=(
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
    *)
      return 0
      ;;
  esac
}

# _hm_argument SUBCOMMAND COUNT
# Complete the argument of a subcommand. COUNT is the number of arguments
# that the subcommand already received.
_hm_argument() {
  local -a candidates

  case $1 in
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
    _hm_options $subcommand
    return 0
  fi

  # The current word is an argument of the subcommand.
  _hm_argument $subcommand ${#positionals}
  return 0
}

# ---------------------------------------------------------------------------
# Registration
# ---------------------------------------------------------------------------

# The completion system has to be initialized first.
if (( $+functions[compdef] )); then
  compdef _hm hm
fi
