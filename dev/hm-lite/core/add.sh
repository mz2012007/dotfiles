#!/usr/bin/env bash
#
# core/add.sh - the add command.
#
# Registers paths for the next generation. The command is registration
# only, it never calculates a hash, never copies content into the store,
# never creates a generation and never modifies the original files.
#
# The module only defines the add function. Sourcing it does not run the
# command.
#

# _add_collect ARGUMENT
# Append the eligible entries of one argument to the candidate arrays.
# Symbolic links and special files are never followed, they are reported
# and skipped.
_add_collect() {
  local argument="$1"
  local normalized path kind

  normalized="$(hm_path_normalize "$argument")" || {
    hm_log_error "Invalid path: $argument"
    return 1
  }

  if [[ ! -e "$normalized" && ! -L "$normalized" ]]; then
    hm_log_error "Path not found: $(hm_path_display "$normalized")"
    return 1
  fi

  if [[ -L "$normalized" ]]; then
    hm_log_error "Symbolic links are not supported: $(hm_path_display "$normalized")"
    return 1
  fi

  if [[ -d "$normalized" ]]; then
    _ADD_CANDIDATES+=("$normalized")
    _ADD_KINDS+=("dir")
    _ADD_ROOTS+=("$normalized")

    while IFS= read -r -d '' path; do
      case "$path" in
        "$HM_DIR" | "$HM_DIR"/*)
          hm_log_warn "Skipping the HM-Lite project directory: $(hm_path_display "$path")"
          continue
          ;;
      esac

      if [[ -L "$path" ]]; then
        hm_log_warn "Skipping symbolic link: $(hm_path_display "$path")"
        continue
      fi

      if [[ -d "$path" ]]; then
        kind="dir"
      elif [[ -f "$path" ]]; then
        kind="file"
      else
        hm_log_warn "Skipping unsupported file type: $(hm_path_display "$path")"
        continue
      fi

      _ADD_CANDIDATES+=("$path")
      _ADD_KINDS+=("$kind")
    done < <(find "$normalized" -mindepth 1 -print0 2>/dev/null)

    return 0
  fi

  if [[ -f "$normalized" ]]; then
    _ADD_CANDIDATES+=("$normalized")
    _ADD_KINDS+=("file")
    return 0
  fi

  hm_log_error "Unsupported file type: $(hm_path_display "$normalized")"
  return 1
}

# _add_load_state KNOWN_VAR PENDING_VAR
# Load the tracked paths and the pending set from the database into the two
# associative arrays named by the caller.
_add_load_state() {
  # The two namerefs write into the arrays of the caller, shellcheck cannot
  # see through them.
  # shellcheck disable=SC2034
  local -n known_ref="$1"
  # shellcheck disable=SC2034
  local -n pending_ref="$2"
  local rows row encoded kind path

  known_ref=()
  pending_ref=()

  if ! hm_db_rows "SELECT hex(path), kind FROM paths;" rows; then
    hm_die "$HM_EX_DB" "Cannot read the tracked paths from the database."
  fi

  while IFS= read -r row; do
    [[ -n "$row" ]] || continue
    encoded="${row%%"$HM_FIELD_SEP"*}"
    kind="${row#*"$HM_FIELD_SEP"}"
    hm_hex_decode path "$encoded"
    # shellcheck disable=SC2034
    known_ref["$path"]="$kind"
  done <<< "$rows"

  if ! hm_db_rows "SELECT hex(path) FROM paths p JOIN pending_paths pp ON pp.path_id = p.id;" rows; then
    hm_die "$HM_EX_DB" "Cannot read the pending paths from the database."
  fi

  while IFS= read -r row; do
    [[ -n "$row" ]] || continue
    hm_hex_decode path "$row"
    # shellcheck disable=SC2034
    pending_ref["$path"]=1
  done <<< "$rows"
}

# add PATH...
# Register the given files and directories for the next generation.
add() {
  local -a args=()
  local argument path kind label
  local -A seen=()
  local -A known=()
  local -A pending=()
  local -A status=()
  local -A candidates=()
  local -A candidate_kind=()
  local -a removed=()
  local new_count=0 requeue_count=0 pending_count=0 removed_count=0
  local discovered=0 errors=0 now

  if [[ $# -eq 0 ]]; then
    hm_die "$HM_EX_USAGE" "Usage: hm add <file|directory...>"
  fi

  for argument in "$@"; do
    case "$argument" in
      -h | --help)
        printf 'Usage: hm add <file|directory...>\n'
        return 0
        ;;
      *)
        args+=("$argument")
        ;;
    esac
  done

  if [[ ${#args[@]} -eq 0 ]]; then
    hm_die "$HM_EX_USAGE" "Usage: hm add <file|directory...>"
  fi

  hm_require_initialized
  hm_lock_acquire exclusive

  _ADD_CANDIDATES=()
  _ADD_KINDS=()
  _ADD_ROOTS=()

  for argument in "${args[@]}"; do
    if ! _add_collect "$argument"; then
      errors=$((errors + 1))
    fi
  done

  if [[ $errors -gt 0 ]]; then
    hm_die "$HM_EX_VALIDATION" "$errors argument(s) could not be registered."
  fi

  # Deduplicate, the same path can be reached through overlapping arguments.
  local index=0
  for index in "${!_ADD_CANDIDATES[@]}"; do
    path="${_ADD_CANDIDATES[$index]}"
    kind="${_ADD_KINDS[$index]}"
    if [[ -z "${seen[$path]:-}" ]]; then
      seen["$path"]=1
      candidates["$path"]=1
      candidate_kind["$path"]="$kind"
    fi
  done

  _add_load_state known pending

  # Classify every candidate.
  for path in "${!candidates[@]}"; do
    if [[ -z "${known[$path]:-}" ]]; then
      status["$path"]="NEW"
      new_count=$((new_count + 1))
    elif [[ -z "${pending[$path]:-}" ]]; then
      status["$path"]="TRACKED"
      requeue_count=$((requeue_count + 1))
    else
      status["$path"]="PENDING"
      pending_count=$((pending_count + 1))
    fi
    discovered=$((discovered + 1))
  done

  # A pending path below one of the given directories that no longer exists
  # is removed from the pending set. The path itself stays in the registry,
  # the history is never touched.
  local root
  for root in "${_ADD_ROOTS[@]}"; do
    for path in "${!pending[@]}"; do
      if [[ "$path" == "$root" || "$path" == "$root/"* ]]; then
        if [[ ! -e "$path" ]]; then
          removed+=("$path")
        fi
      fi
    done
  done
  removed_count=${#removed[@]}

  # Preview.
  printf '%sPaths selected for registration:%s\n' "$HM_C_OUT_BOLD" "$HM_C_OUT_RESET"
  printf '\n'

  # The preview is NUL delimited, a file name may contain a newline.
  local sorted_path
  while IFS= read -r -d '' sorted_path; do
    label="${status[$sorted_path]:-}"
    case "$label" in
      NEW) printf '  %s[NEW]%s      %s\n' "$HM_C_OUT_GREEN" "$HM_C_OUT_RESET" "$(hm_path_display "$sorted_path")" ;;
      TRACKED) printf '  %s[TRACKED]%s  %s\n' "$HM_C_OUT_YELLOW" "$HM_C_OUT_RESET" "$(hm_path_display "$sorted_path")" ;;
      PENDING) printf '  %s[PENDING]%s  %s\n' "$HM_C_OUT_BLUE" "$HM_C_OUT_RESET" "$(hm_path_display "$sorted_path")" ;;
    esac
  done < <(printf '%s\0' "${!candidates[@]}" | sort -z)

  if [[ $removed_count -gt 0 ]]; then
    while IFS= read -r -d '' sorted_path; do
      printf '  %s[REMOVED]%s  %s\n' "$HM_C_OUT_RED" "$HM_C_OUT_RESET" "$(hm_path_display "$sorted_path")"
    done < <(printf '%s\0' "${removed[@]}" | sort -z)
  fi

  printf '\n'
  printf '%d paths discovered\n' "$discovered"
  printf '%s%d new paths%s\n' "$HM_C_OUT_GREEN" "$new_count" "$HM_C_OUT_RESET"
  printf '%d paths queued again\n' "$requeue_count"
  printf '%d paths already pending\n' "$pending_count"
  printf '%d paths removed from the pending set\n' "$removed_count"
  printf '\n'

  if [[ $discovered -eq 0 && $removed_count -eq 0 ]]; then
    hm_log_info "Nothing to register."
    return 0
  fi

  if ! hm_confirm "Continue? [y/N]"; then
    hm_log_info "Cancelled, nothing was changed."
    return "$HM_EX_DECLINED"
  fi

  now="$(hm_now_epoch)"

  # One transaction for the registration and for the pending set.
  {
    while IFS= read -r -d '' sorted_path; do
      printf 'INSERT INTO paths (path, kind, created_at) VALUES (%s, %s, %s) ON CONFLICT(path) DO UPDATE SET kind = excluded.kind;\n' \
        "$(hm_sql_quote "$sorted_path")" \
        "$(hm_sql_quote "${candidate_kind[$sorted_path]:-file}")" \
        "$now"
      printf 'INSERT OR IGNORE INTO pending_paths (path_id, added_at) SELECT id, %s FROM paths WHERE path = %s;\n' \
        "$now" "$(hm_sql_quote "$sorted_path")"
    done < <(printf '%s\0' "${!candidates[@]}" | sort -z)

    if [[ $removed_count -gt 0 ]]; then
      printf 'DELETE FROM pending_paths WHERE path_id IN (SELECT id FROM paths WHERE path IN ('
      local first=1 removed_path
      for removed_path in "${removed[@]}"; do
        if [[ $first -eq 1 ]]; then
          first=0
        else
          printf ','
        fi
        printf '%s' "$(hm_sql_quote "$removed_path")"
      done
      printf '));\n'
    fi
  } | hm_db_tx || hm_die "$HM_EX_DB" "The registration failed, nothing was changed."

  hm_log_success "Registered $new_count new path(s), queued $requeue_count path(s) again."
  if [[ $removed_count -gt 0 ]]; then
    hm_log_success "Removed $removed_count path(s) from the pending set."
  fi
  hm_log_info "Run 'hm gen' to create a generation from the pending paths."

  return 0
}
