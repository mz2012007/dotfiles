#!/usr/bin/env bash
#
# core/clean.sh - the clean command.
#
# Removes the content objects that no generation uses any more.
#
# The reference analysis is exact. An object is removed when no generation
# entry points at it, the database rows of the unreferenced contents are
# removed with it. Objects that a generation needs but that are missing
# from the store are reported, they are never removed silently because
# they are the symptom of a damaged project.
#

# --- Helpers ---------------------------------------------------------------

# _clean_usage
_clean_usage() {
  cat <<'EOF'
Usage: hm clean [options]

Remove the content objects that no generation uses any more.

Options:
  --dry-run      Show what would be removed, change nothing
  --yes, -y      Do not ask for a confirmation
  -h, --help     Show this help
EOF
}

# --- The command -----------------------------------------------------------

# clean - remove the unreferenced content objects.
clean() {
  local assume_yes=0
  local dry_run=0
  local argument

  while [[ $# -gt 0 ]]; do
    argument="$1"
    case "$argument" in
      --dry-run)
        dry_run=1
        shift
        ;;
      --yes | -y)
        assume_yes=1
        shift
        ;;
      -h | --help)
        _clean_usage
        return 0
        ;;
      *)
        hm_die "$HM_EX_USAGE" "Unknown option for 'hm clean': $argument"
        ;;
    esac
  done

  hm_require_initialized
  hm_lock_acquire exclusive

  # --- The hashes that a generation uses ------------------------------------
  local -A referenced=()
  local rows row hash id

  if ! hm_db_rows "
    SELECT DISTINCT f.hash
      FROM generation_entries ge
      JOIN files f ON f.id = ge.file_id;" rows; then
    hm_die "$HM_EX_DB" "Cannot read the referenced content objects, nothing was removed."
  fi

  while IFS= read -r row; do
    [[ -n "$row" ]] || continue
    referenced["$row"]=1
  done <<< "$rows"

  # --- The objects that the store holds -------------------------------------
  local -a objects=()
  local -A in_store=()
  local object_hashes=""

  if ! hm_store_object_hashes object_hashes; then
    hm_die "$HM_EX_IO" "Cannot read the content store, nothing was removed."
  fi

  while IFS= read -r hash; do
    [[ -n "$hash" ]] || continue
    in_store["$hash"]=1
    if [[ -z "${referenced[$hash]:-}" ]]; then
      objects+=("$hash")
    fi
  done <<< "$object_hashes"

  # --- The database rows that no generation uses -----------------------------
  local -a rows_to_remove=()

  if ! hm_db_rows "
    SELECT f.id, f.hash
      FROM files f
     WHERE f.id NOT IN (SELECT file_id FROM generation_entries WHERE file_id IS NOT NULL);" rows; then
    hm_die "$HM_EX_DB" "Cannot read the unreferenced rows, nothing was removed."
  fi

  while IFS= read -r row; do
    [[ -n "$row" ]] || continue
    IFS="$HM_FIELD_SEP" read -r id hash <<< "$row"
    rows_to_remove+=("$id")
  done <<< "$rows"

  # --- The objects that a generation needs but that are missing --------------
  local -a missing=()

  for hash in "${!referenced[@]}"; do
    if [[ -z "${in_store[$hash]:-}" ]]; then
      missing+=("$hash")
    fi
  done

  # --- Preview ---------------------------------------------------------------
  printf '%sClean preview:%s\n' "$HM_C_OUT_BOLD" "$HM_C_OUT_RESET"
  printf '\n'
  printf '  %s%d unreferenced object(s) in the store%s\n' \
    "$HM_C_OUT_YELLOW" "${#objects[@]}" "$HM_C_OUT_RESET"
  printf '  %d unreferenced row(s) in the database\n' "${#rows_to_remove[@]}"
  printf '  %s%d missing object(s) that a generation needs%s\n' \
    "$HM_C_OUT_RED" "${#missing[@]}" "$HM_C_OUT_RESET"
  printf '\n'

  local index
  for index in "${objects[@]}"; do
    printf '  %sREMOVE%s  %s\n' "$HM_C_OUT_YELLOW" "$HM_C_OUT_RESET" "$index"
  done

  for index in "${missing[@]}"; do
    printf '  %sMISSING%s %s\n' "$HM_C_OUT_RED" "$HM_C_OUT_RESET" "$index"
  done

  if [[ ${#missing[@]} -gt 0 ]]; then
    hm_log_warn "${#missing[@]} object(s) that a generation needs are missing from the store."
    hm_log_warn "Restore them from a backup, the generations cannot be materialized without them."
  fi

  if [[ ${#objects[@]} -eq 0 && ${#rows_to_remove[@]} -eq 0 ]]; then
    hm_log_info "The content store holds no garbage, nothing was removed."
    return 0
  fi

  if [[ $dry_run -eq 1 ]]; then
    hm_log_info "Dry run, nothing was removed."
    return 0
  fi

  if [[ $assume_yes -eq 0 ]]; then
    if ! hm_confirm "Remove the unreferenced content objects? [y/N]"; then
      hm_log_info "Cancelled, nothing was removed."
      return "$HM_EX_DECLINED"
    fi
  fi

  # --- Remove the objects ---------------------------------------------------
  local removed=0
  for hash in "${objects[@]}"; do
    if hm_store_remove "$hash"; then
      removed=$((removed + 1))
    else
      hm_log_warn "Cannot remove the content object: $hash"
    fi
  done

  # --- Remove the database rows ---------------------------------------------
  if [[ ${#rows_to_remove[@]} -gt 0 ]]; then
    {
      printf 'DELETE FROM files WHERE id IN ('
      local first=1
      for id in "${rows_to_remove[@]}"; do
        if [[ $first -eq 1 ]]; then
          first=0
        else
          printf ','
        fi
        printf '%s' "$id"
      done
      printf ');\n'
    } | hm_db_tx || hm_die "$HM_EX_DB" "Cannot remove the unreferenced rows, nothing was changed."
  fi

  if [[ ${#missing[@]} -gt 0 ]]; then
    hm_log_warn "The missing objects were not touched."
  fi

  hm_log_success "Removed $removed object(s) and ${#rows_to_remove[@]} database row(s)."

  return 0
}
