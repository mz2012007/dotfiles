#!/usr/bin/env bash
#
# core/list.sh - the list command.
#
# Read only views on the project state. The command never changes anything,
# it therefore only takes a shared lock.
#
# The module only defines the list function. Sourcing it does not run the
# command.
#

# _list_usage
_list_usage() {
  cat <<'EOF'
Usage: hm list [options]

Show the state of the project.

Options:
  --generation ID   Show the entries of a single generation
  --pending         Show the paths that are queued for the next generation
  --paths           Show the tracked paths
  --store           Show the statistics of the content store
  -h, --help        Show this help
EOF
}

# _list_generations - print the overview of every generation.
_list_generations() {
  local rows row id created entries objects name

  printf '%-6s %-21s %8s %8s  %s\n' "ID" "CREATED" "ENTRIES" "OBJECTS" "NAME"

  if ! hm_db_rows "
    SELECT g.id,
           g.created_at,
           (SELECT COUNT(*) FROM generation_entries ge WHERE ge.generation_id = g.id),
           (SELECT COUNT(DISTINCT ge.file_id) FROM generation_entries ge WHERE ge.generation_id = g.id AND ge.file_id IS NOT NULL),
           COALESCE(g.name, '')
      FROM generations g
     ORDER BY g.created_at DESC, g.id DESC;" rows; then
    hm_die "$HM_EX_DB" "Cannot read the generations from the database."
  fi

  while IFS= read -r row; do
    [[ -n "$row" ]] || continue
    IFS="$HM_FIELD_SEP" read -r id created entries objects name <<< "$row"

    printf '%-6s %-21s %8s %8s  %s\n' \
      "$id" "$(hm_format_epoch "$created" || printf '%s' "$created")" \
      "$entries" "$objects" "${name:-(unnamed)}"
  done <<< "$rows"
}

# _list_generation ID - print the entries of a single generation.
_list_generation() {
  local id="$1"
  local rows row encoded entry_type hash_hex mode size path hash created

  created="$(hm_db_scalar "SELECT created_at FROM generations WHERE id = $(hm_sql_int "$id");")" ||
    hm_die "$HM_EX_DB" "Cannot read the generation $id from the database."

  printf 'Generation %s, created %s\n' "$id" "$(hm_format_epoch "$created" || printf '%s' "$created")"
  printf '\n'
  printf '%-40s %-6s %-6s %10s  %s\n' "PATH" "TYPE" "MODE" "SIZE" "HASH"

  if ! hm_gen_entries "$id" rows; then
    hm_die "$HM_EX_DB" "Cannot read the entries of the generation $id."
  fi

  while IFS= read -r row; do
    [[ -n "$row" ]] || continue
    IFS="$HM_FIELD_SEP" read -r encoded entry_type hash_hex mode _uid _gid _mtime size <<< "$row"

    hm_hex_decode path "$encoded"
    hm_hex_decode hash "$hash_hex"

    if [[ -n "$hash" ]]; then
      printf '%-40s %-6s %-6s %10s  %s\n' \
        "$(hm_path_display "$path")" "$entry_type" \
        "$(hm_mode_to_octal "$mode" || printf '%s' "$mode")" \
        "$size" "${hash:0:12}"
    else
      printf '%-40s %-6s %-6s %10s  %s\n' \
        "$(hm_path_display "$path")" "$entry_type" \
        "$(hm_mode_to_octal "$mode" || printf '%s' "$mode")" \
        "$size" "-"
    fi
  done <<< "$rows"
}

# _list_pending - print the paths that are queued for the next generation.
_list_pending() {
  local rows row encoded kind added path

  printf '%-40s %-6s %s\n' "PATH" "TYPE" "ADDED"

  if ! hm_db_rows "
    SELECT hex(p.path),
           p.kind,
           pp.added_at
      FROM pending_paths pp
      JOIN paths p ON p.id = pp.path_id
     ORDER BY p.path;" rows; then
    hm_die "$HM_EX_DB" "Cannot read the pending paths from the database."
  fi

  while IFS= read -r row; do
    [[ -n "$row" ]] || continue
    IFS="$HM_FIELD_SEP" read -r encoded kind added <<< "$row"

    hm_hex_decode path "$encoded"

    printf '%-40s %-6s %s\n' \
      "$(hm_path_display "$path")" "$kind" "$(hm_format_epoch "$added" || printf '%s' "$added")"
  done <<< "$rows"
}

# _list_paths - print the tracked paths.
_list_paths() {
  local rows row encoded kind created path

  printf '%-40s %-6s %s\n' "PATH" "TYPE" "REGISTERED"

  if ! hm_db_rows "
    SELECT hex(path), kind, created_at
      FROM paths
     ORDER BY path;" rows; then
    hm_die "$HM_EX_DB" "Cannot read the tracked paths from the database."
  fi

  while IFS= read -r row; do
    [[ -n "$row" ]] || continue
    IFS="$HM_FIELD_SEP" read -r encoded kind created <<< "$row"

    hm_hex_decode path "$encoded"

    printf '%-40s %-6s %s\n' \
      "$(hm_path_display "$path")" "$kind" "$(hm_format_epoch "$created" || printf '%s' "$created")"
  done <<< "$rows"
}

# _list_store - print the statistics of the content store.
_list_store() {
  local objects size referenced orphans generations paths_count pending_count

  objects="$(hm_store_count)" || hm_die "$HM_EX_IO" "Cannot read the content store."
  size="$(hm_store_total_size)" || hm_die "$HM_EX_IO" "Cannot read the content store."

  referenced="$(hm_db_scalar "SELECT COUNT(DISTINCT hash) FROM files;")" ||
    hm_die "$HM_EX_DB" "Cannot read the database."
  generations="$(hm_db_scalar "SELECT COUNT(*) FROM generations;")" ||
    hm_die "$HM_EX_DB" "Cannot read the database."
  paths_count="$(hm_db_scalar "SELECT COUNT(*) FROM paths;")" ||
    hm_die "$HM_EX_DB" "Cannot read the database."
  pending_count="$(hm_db_scalar "SELECT COUNT(*) FROM pending_paths;")" ||
    hm_die "$HM_EX_DB" "Cannot read the database."

  orphans=$((objects - referenced))
  [[ $orphans -ge 0 ]] || orphans=0

  printf '%-24s %s\n' "Objects in the store:" "$objects"
  printf '%-24s %s\n' "Size in bytes:" "$size"
  printf '%-24s %s\n' "Objects in the database:" "$referenced"
  printf '%-24s %s\n' "Unreferenced objects:" "$orphans"
  printf '%-24s %s\n' "Generations:" "$generations"
  printf '%-24s %s\n' "Tracked paths:" "$paths_count"
  printf '%-24s %s\n' "Pending paths:" "$pending_count"
}

# list - show the state of the project.
list() {
  local mode="generations"
  local generation=""
  local argument

  while [[ $# -gt 0 ]]; do
    argument="$1"
    case "$argument" in
      --generation)
        [[ $# -ge 2 ]] || hm_die "$HM_EX_USAGE" "--generation requires a value."
        generation="$2"
        mode="generation"
        shift 2
        ;;
      --generation=*)
        generation="${argument#*=}"
        mode="generation"
        shift
        ;;
      --pending)
        mode="pending"
        shift
        ;;
      --paths)
        mode="paths"
        shift
        ;;
      --store)
        mode="store"
        shift
        ;;
      -h | --help)
        _list_usage
        return 0
        ;;
      *)
        hm_die "$HM_EX_USAGE" "Unknown option for 'hm list': $argument"
        ;;
    esac
  done

  hm_require_initialized
  hm_lock_acquire shared

  case "$mode" in
    generation)
      if ! hm_gen_exists "$generation"; then
        hm_die "$HM_EX_STATE" "There is no generation with the id $generation."
      fi
      _list_generation "$generation"
      ;;
    pending)
      _list_pending
      ;;
    paths)
      _list_paths
      ;;
    store)
      _list_store
      ;;
    *)
      _list_generations
      ;;
  esac

  return 0
}
