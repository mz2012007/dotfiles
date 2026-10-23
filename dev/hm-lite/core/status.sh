#!/usr/bin/env bash
#
# core/status.sh - the status command.
#
# Read only dashboard of the project: the project itself, the content store
# and every generation. The command never changes anything, it therefore
# only takes a shared lock.
#
# The store section classifies every object in one pass: present and
# referenced, present but unreferenced (the garbage of "hm clean"), or
# missing (a generation needs it but the store does not have it). The size
# of a generation is the size of the distinct content objects it
# references, so content that several paths or generations share is
# counted once and the generation sizes never add up to more than the
# store holds.
#
# The module only defines the status function. Sourcing it does not run the
# command.
#

# --- Helpers ---------------------------------------------------------------

# _status_usage
_status_usage() {
  cat <<'EOF'
Usage: hm status [options]

Show the project, the content store and the generations.

Options:
  --profile NAME  Show a single profile (default: the active profile, then every profile)
  -h, --help      Show this help
EOF
}

# _status_count SQL - print the scalar value of a database query.
_status_count() {
  local value

  value="$(hm_db_scalar "$1")" || hm_die "$HM_EX_DB" "Cannot read the database."
  printf '%s\n' "$value"
}

# _status_store_objects VARIABLE
# Store one row with the statistics of the content store in VARIABLE. The
# fields are separated by HM_FIELD_SEP:
#
#   objects  store bytes  referenced  referenced bytes
#   unreferenced  unreferenced bytes  missing  missing bytes
#
# "Referenced" means that the object is present in the store and used by at
# least one generation, "unreferenced" that only the store has it (the
# garbage of "hm clean") and "missing" that a generation needs it but the
# store does not have it. A failed query aborts the command instead of
# returning an empty row.
_status_store_objects() {
  local -n hm__status_store="$1"
  local rows record hash size
  local objects=0 store_bytes=0
  local referenced=0 referenced_bytes=0
  local unreferenced=0 unreferenced_bytes=0
  local missing=0 missing_bytes=0
  local hashes=""
  local -A known=()
  local -A seen=()

  if ! hm_db_rows "
    SELECT DISTINCT f.hash, f.size
      FROM files f
      JOIN generation_entries ge ON ge.file_id = f.id;" rows; then
    hm_die "$HM_EX_DB" "Cannot read the content objects from the database."
  fi

  while IFS= read -r record; do
    [[ -n "$record" ]] || continue
    IFS="$HM_FIELD_SEP" read -r hash size <<< "$record"
    known["$hash"]="$size"
  done <<< "$rows"

  hm_store_object_hashes hashes || hm_die "$HM_EX_IO" "Cannot read the content store."

  while IFS= read -r hash; do
    [[ -n "$hash" ]] || continue

    objects=$((objects + 1))
    size="$(stat -c '%s' -- "$(hm_store_path "$hash")" 2>/dev/null || printf '0')"
    store_bytes=$((store_bytes + size))
    seen["$hash"]=1

    if [[ -n "${known[$hash]+set}" ]]; then
      referenced=$((referenced + 1))
      referenced_bytes=$((referenced_bytes + size))
    else
      unreferenced=$((unreferenced + 1))
      unreferenced_bytes=$((unreferenced_bytes + size))
    fi
  done <<< "$hashes"

  for hash in "${!known[@]}"; do
    [[ -n "${seen[$hash]+set}" ]] && continue
    missing=$((missing + 1))
    missing_bytes=$((missing_bytes + known[$hash]))
  done

  # The caller owns the variable, shellcheck cannot see the indirection.
  # shellcheck disable=SC2034
  hm__status_store="$objects$HM_FIELD_SEP$store_bytes$HM_FIELD_SEP$referenced$HM_FIELD_SEP$referenced_bytes$HM_FIELD_SEP$unreferenced$HM_FIELD_SEP$unreferenced_bytes$HM_FIELD_SEP$missing$HM_FIELD_SEP$missing_bytes"
  return 0
}

# _status_render [PROFILE] - print the dashboard, restricted to a profile
# when one is given.
_status_render() {
  local profile="${1:-}" where="" generation_where=""
  local row objects store_bytes referenced referenced_bytes
  local unreferenced unreferenced_bytes missing missing_bytes
  local generations paths_count pending_count selected selected_label store_root

  if [[ -n "$profile" ]]; then
    where="WHERE pr.name = $(hm_sql_quote "$profile")"
    generation_where="WHERE pr.name = $(hm_sql_quote "$profile")"
  fi

  generations="$(_status_count "
    SELECT COUNT(*)
      FROM generations g
      JOIN profiles pr ON pr.id = g.profile_id
      $generation_where;")"
  paths_count="$(_status_count "
    SELECT COUNT(*)
      FROM paths p
      JOIN path_profiles x ON x.path_id = p.id
      JOIN profiles pr ON pr.id = x.profile_id
      $where;")"
  pending_count="$(_status_count "
    SELECT COUNT(*)
      FROM pending_paths pp
      JOIN profiles pr ON pr.id = pp.profile_id
      $where;")"
  selected="$(hm_gen_selected "$profile")"
  selected_label=""
  if [[ -n "$selected" ]]; then
    if [[ -n "$profile" ]]; then
      selected_label="$(hm_gen_number "$selected")" || selected_label="$selected"
    else
      selected_label="$(hm_gen_label "$selected")" || selected_label="$selected"
    fi
  fi

  _status_store_objects row
  IFS="$HM_FIELD_SEP" read -r objects store_bytes referenced referenced_bytes \
    unreferenced unreferenced_bytes missing missing_bytes <<< "$row"

  store_root="$(hm_store_root)"

  printf '%sHM-Lite status%s\n' "$HM_C_OUT_HEADING" "$HM_C_OUT_RESET"
  printf '\n'
  printf '  %s%-16s%s %s\n' "$HM_C_OUT_LABEL" "Project:" "$HM_C_OUT_RESET" "$HM_DIR"
  if [[ -n "$profile" ]]; then
    printf '  %s%-16s%s %s\n' "$HM_C_OUT_LABEL" "Profile:" "$HM_C_OUT_RESET" "$profile"
  else
    printf '  %s%-16s%s %s\n' "$HM_C_OUT_LABEL" "Profile:" "$HM_C_OUT_RESET" "all"
  fi
  printf '  %s%-16s%s %s\n' "$HM_C_OUT_LABEL" "Generations:" "$HM_C_OUT_RESET" "$generations"
  if [[ -n "$selected" ]]; then
    printf '  %s%-16s%s %s%s%s\n' "$HM_C_OUT_LABEL" "Selected:" "$HM_C_OUT_RESET" \
      "$HM_C_OUT_CYAN" "$selected_label" "$HM_C_OUT_RESET"
  else
    printf '  %s%-16s%s %s\n' "$HM_C_OUT_LABEL" "Selected:" "$HM_C_OUT_RESET" "-"
  fi
  printf '  %s%-16s%s %s\n' "$HM_C_OUT_LABEL" "Tracked paths:" "$HM_C_OUT_RESET" "$paths_count"
  printf '  %s%-16s%s %s\n' "$HM_C_OUT_LABEL" "Pending paths:" "$HM_C_OUT_RESET" "$pending_count"
  printf '\n'

  printf '%sStore%s\n' "$HM_C_OUT_HEADING" "$HM_C_OUT_RESET"
  printf '\n'
  printf '  %s%-16s%s %s\n' "$HM_C_OUT_LABEL" "Location:" "$HM_C_OUT_RESET" "$store_root"
  printf '  %s%-16s%s %s\n' "$HM_C_OUT_LABEL" "Objects:" "$HM_C_OUT_RESET" "$objects"
  printf '  %s%-16s%s %s (%s bytes)\n' "$HM_C_OUT_LABEL" "Size:" "$HM_C_OUT_RESET" \
    "$(hm_format_bytes "$store_bytes")" "$store_bytes"
  printf '  %s%-16s%s %s object(s), %s (%s bytes)\n' "$HM_C_OUT_LABEL" "Referenced:" "$HM_C_OUT_RESET" \
    "$referenced" "$(hm_format_bytes "$referenced_bytes")" "$referenced_bytes"

  if (( unreferenced > 0 )); then
    printf '  %s%-16s%s %s%s object(s), %s (%s bytes)%s\n' "$HM_C_OUT_LABEL" "Unreferenced:" "$HM_C_OUT_RESET" \
      "$HM_C_OUT_YELLOW" "$unreferenced" "$(hm_format_bytes "$unreferenced_bytes")" "$unreferenced_bytes" "$HM_C_OUT_RESET"
  else
    printf '  %s%-16s%s %s%s object(s), %s (%s bytes)%s\n' "$HM_C_OUT_LABEL" "Unreferenced:" "$HM_C_OUT_RESET" \
      "$HM_C_OUT_GREEN" "$unreferenced" "$(hm_format_bytes "$unreferenced_bytes")" "$unreferenced_bytes" "$HM_C_OUT_RESET"
  fi

  if (( missing > 0 )); then
    printf '  %s%-16s%s %s%s object(s), %s (%s bytes)%s\n' "$HM_C_OUT_LABEL" "Missing:" "$HM_C_OUT_RESET" \
      "$HM_C_OUT_RED" "$missing" "$(hm_format_bytes "$missing_bytes")" "$missing_bytes" "$HM_C_OUT_RESET"
  else
    printf '  %s%-16s%s %s%s object(s), %s (%s bytes)%s\n' "$HM_C_OUT_LABEL" "Missing:" "$HM_C_OUT_RESET" \
      "$HM_C_OUT_GREEN" "$missing" "$(hm_format_bytes "$missing_bytes")" "$missing_bytes" "$HM_C_OUT_RESET"
  fi

  if (( unreferenced > 0 )); then
    printf '  %sRun "hm clean" to remove the unreferenced objects.%s\n' \
      "$HM_C_OUT_YELLOW" "$HM_C_OUT_RESET"
  fi
  printf '\n'

  printf '%sGenerations%s\n' "$HM_C_OUT_HEADING" "$HM_C_OUT_RESET"
  printf '\n'
  hm_profile_tree "$profile" "status"

  if (( missing > 0 )); then
    hm_log_warn "$missing content object(s) are missing from the store."
  fi
}

# --- The command -----------------------------------------------------------

# status - print the dashboard of the project.
status() {
  local argument
  local profile=""

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
      -h | --help)
        _status_usage
        return 0
        ;;
      -*)
        hm_die "$HM_EX_USAGE" "Unknown option for 'hm status': $argument"
        ;;
      *)
        hm_die "$HM_EX_USAGE" "Usage: hm status"
        ;;
    esac
  done

  hm_require_initialized
  hm_lock_acquire shared

  profile="$(hm_profile_scope "$profile")" || exit $?
  if [[ -n "$profile" ]]; then
    hm_profile_require "$profile" > /dev/null
  fi

  hm_log_debug "Collecting the project status."
  _status_render "$profile"

  return 0
}
