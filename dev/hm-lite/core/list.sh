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
  --profile NAME    Show a single profile (default: the active profile, then every profile)
  --generation ID   Show the entries of a single generation
  --pending         Show the paths that are queued for the next generation
  --paths           Show the tracked paths
  --store           Show the statistics of the content store
  -h, --help        Show this help
EOF
}

# _list_generations [PROFILE] - print the overview of the generations.
_list_generations() {
  local profile="${1:-}" where="" rows row id profile_name created entries objects name

  if [[ -n "$profile" ]]; then
    where="WHERE pr.name = $(hm_sql_quote "$profile")"
  fi

  printf '%s%-6s %-16s %-21s %8s %8s  %s%s\n' "$HM_C_OUT_HEADING" \
    "ID" "PROFILE" "CREATED" "ENTRIES" "OBJECTS" "NAME" "$HM_C_OUT_RESET"

  if ! hm_db_rows "
    SELECT g.id,
           pr.name,
           g.created_at,
           (SELECT COUNT(*) FROM generation_entries ge WHERE ge.generation_id = g.id),
           (SELECT COUNT(DISTINCT ge.file_id) FROM generation_entries ge WHERE ge.generation_id = g.id AND ge.file_id IS NOT NULL),
           COALESCE(g.name, '')
      FROM generations g
      JOIN profiles pr ON pr.id = g.profile_id
      $where
     ORDER BY g.created_at DESC, g.id DESC;" rows; then
    hm_die "$HM_EX_DB" "Cannot read the generations from the database."
  fi

  while IFS= read -r row; do
    [[ -n "$row" ]] || continue
    IFS="$HM_FIELD_SEP" read -r id profile_name created entries objects name <<< "$row"

    printf '%-6s %-16s %-21s %8s %8s  %s\n' \
      "$id" "$profile_name" "$(hm_format_epoch "$created" || printf '%s' "$created")" \
      "$entries" "$objects" "${name:-(unnamed)}"
  done <<< "$rows"
}

# _list_generation ID - print the entries of a single generation.
_list_generation() {
  local id="$1"
  local rows row encoded entry_type hash_hex mode size path hash created profile_name

  created="$(hm_db_scalar "SELECT created_at FROM generations WHERE id = $(hm_sql_int "$id");")" ||
    hm_die "$HM_EX_DB" "Cannot read the generation $id from the database."
  profile_name="$(hm_profile_of_generation "$id")"

  printf 'Generation %s%s%s, created %s\n' "$HM_C_OUT_CYAN" "$id" "$HM_C_OUT_RESET" \
    "$(hm_format_epoch "$created" || printf '%s' "$created")"
  printf '%sProfile:%s %s\n' "$HM_C_OUT_LABEL" "$HM_C_OUT_RESET" "$profile_name"
  printf '\n'
  printf '%s%-40s %-6s %-6s %10s  %s%s\n' "$HM_C_OUT_HEADING" \
    "PATH" "TYPE" "MODE" "SIZE" "HASH" "$HM_C_OUT_RESET"

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

# _list_pending [PROFILE] - print the paths that are queued for the next
# generation of the profile, or of every profile.
_list_pending() {
  local profile="${1:-}" where="" rows row encoded kind added path profile_name

  if [[ -n "$profile" ]]; then
    where="WHERE pr.name = $(hm_sql_quote "$profile")"
  fi

  printf '%s%-40s %-16s %-6s %s%s\n' "$HM_C_OUT_HEADING" \
    "PATH" "PROFILE" "TYPE" "ADDED" "$HM_C_OUT_RESET"

  if ! hm_db_rows "
    SELECT hex(p.path),
           pr.name,
           p.kind,
           pp.added_at
      FROM pending_paths pp
      JOIN paths p ON p.id = pp.path_id
      JOIN profiles pr ON pr.id = pp.profile_id
      $where
     ORDER BY pr.name, p.path;" rows; then
    hm_die "$HM_EX_DB" "Cannot read the pending paths from the database."
  fi

  while IFS= read -r row; do
    [[ -n "$row" ]] || continue
    IFS="$HM_FIELD_SEP" read -r encoded profile_name kind added <<< "$row"

    hm_hex_decode path "$encoded"

    printf '%-40s %-16s %-6s %s\n' \
      "$(hm_path_display "$path")" "$profile_name" "$kind" \
      "$(hm_format_epoch "$added" || printf '%s' "$added")"
  done <<< "$rows"
}

# _list_paths [PROFILE] - print the tracked paths. A path that belongs to
# several profiles is printed once, with the profiles it belongs to.
_list_paths() {
  local profile="${1:-}" where="" rows row encoded kind created path profiles

  if [[ -n "$profile" ]]; then
    where="WHERE pr.name = $(hm_sql_quote "$profile")"
  fi

  printf '%s%-40s %-20s %-6s %s%s\n' "$HM_C_OUT_HEADING" \
    "PATH" "PROFILES" "TYPE" "REGISTERED" "$HM_C_OUT_RESET"

  if ! hm_db_rows "
    SELECT hex(p.path),
           GROUP_CONCAT(pr.name, ',') AS profiles,
           p.kind,
           p.created_at
      FROM paths p
      JOIN path_profiles x ON x.path_id = p.id
      JOIN profiles pr ON pr.id = x.profile_id
      $where
     GROUP BY p.id
     ORDER BY p.path;" rows; then
    hm_die "$HM_EX_DB" "Cannot read the tracked paths from the database."
  fi

  while IFS= read -r row; do
    [[ -n "$row" ]] || continue
    IFS="$HM_FIELD_SEP" read -r encoded profiles kind created <<< "$row"

    hm_hex_decode path "$encoded"

    printf '%-40s %-20s %-6s %s\n' \
      "$(hm_path_display "$path")" "$profiles" "$kind" \
      "$(hm_format_epoch "$created" || printf '%s' "$created")"
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

  printf '%s%-24s%s %s\n' "$HM_C_OUT_LABEL" "Objects in the store:" "$HM_C_OUT_RESET" "$objects"
  printf '%s%-24s%s %s\n' "$HM_C_OUT_LABEL" "Size in bytes:" "$HM_C_OUT_RESET" "$size"
  printf '%s%-24s%s %s\n' "$HM_C_OUT_LABEL" "Objects in the database:" "$HM_C_OUT_RESET" "$referenced"
  if [[ "$orphans" -gt 0 ]]; then
    printf '%s%-24s%s %s%s%s\n' "$HM_C_OUT_LABEL" "Unreferenced objects:" "$HM_C_OUT_RESET" "$HM_C_OUT_YELLOW" "$orphans" "$HM_C_OUT_RESET"
  else
    printf '%s%-24s%s %s\n' "$HM_C_OUT_LABEL" "Unreferenced objects:" "$HM_C_OUT_RESET" "$orphans"
  fi
  printf '%s%-24s%s %s\n' "$HM_C_OUT_LABEL" "Generations:" "$HM_C_OUT_RESET" "$generations"
  printf '%s%-24s%s %s\n' "$HM_C_OUT_LABEL" "Tracked paths:" "$HM_C_OUT_RESET" "$paths_count"
  printf '%s%-24s%s %s\n' "$HM_C_OUT_LABEL" "Pending paths:" "$HM_C_OUT_RESET" "$pending_count"
}

# list - show the state of the project.
list() {
  local mode="generations"
  local generation=""
  local profile=""
  local argument

  while [[ $# -gt 0 ]]; do
    argument="$1"
    case "$argument" in
      --profile)
        [[ $# -ge 2 ]] || hm_die "$HM_EX_USAGE" "--profile requires a value."
        profile="$2"
        shift 2
        ;;
      --profile=*)
        profile="${argument#*=}"
        shift
        ;;
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

  profile="$(hm_profile_scope "$profile")"
  if [[ -n "$profile" ]]; then
    hm_profile_require "$profile" > /dev/null
  fi

  case "$mode" in
    generation)
      if ! hm_gen_exists "$generation"; then
        hm_die "$HM_EX_STATE" "There is no generation with the id $generation."
      fi
      if [[ -n "$profile" && "$(hm_profile_of_generation "$generation")" != "$profile" ]]; then
        hm_die "$HM_EX_VALIDATION" "The generation $generation does not belong to the profile $profile."
      fi
      _list_generation "$generation"
      ;;
    pending)
      _list_pending "$profile"
      ;;
    paths)
      _list_paths "$profile"
      ;;
    store)
      _list_store
      ;;
    *)
      _list_generations "$profile"
      ;;
  esac

  return 0
}
