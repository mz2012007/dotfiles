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
  local row hash id

  while IFS= read -r row; do
    [[ -n "$row" ]] || continue
    referenced["$row"]=1
  done < <(hm_db_query "
    SELECT DISTINCT f.hash
      FROM generation_entries ge
      JOIN files f ON f.id = ge.file_id;")

  # --- The objects that the store holds -------------------------------------
  local -a objects=()
  local -A in_store=()

  while IFS= read -r hash; do
    [[ -n "$hash" ]] || continue
    in_store["$hash"]=1
    if [[ -z "${referenced[$hash]:-}" ]]; then
      objects+=("$hash")
    fi
  done < <(hm_store_object_hashes)

  # --- The database rows that no generation uses -----------------------------
  local -a rows=()

  while IFS= read -r row; do
    [[ -n "$row" ]] || continue
    IFS="$HM_FIELD_SEP" read -r id hash <<< "$row"
    rows+=("$id")
  done < <(hm_db_query "
    SELECT f.id, f.hash
      FROM files f
     WHERE f.id NOT IN (SELECT file_id FROM generation_entries WHERE file_id IS NOT NULL);")

  # --- The objects that a generation needs but that are missing --------------
  local -a missing=()

  for hash in "${!referenced[@]}"; do
    if [[ -z "${in_store[$hash]:-}" ]]; then
      missing+=("$hash")
    fi
  done

  # --- Preview ---------------------------------------------------------------
  printf 'Clean preview:\n'
  printf '\n'
  printf '  %d unreferenced object(s) in the store\n' "${#objects[@]}"
  printf '  %d unreferenced row(s) in the database\n' "${#rows[@]}"
  printf '  %d missing object(s) that a generation needs\n' "${#missing[@]}"
  printf '\n'

  local index
  for index in "${objects[@]}"; do
    printf '  REMOVE  %s\n' "$index"
  done

  for index in "${missing[@]}"; do
    printf '  MISSING %s\n' "$index"
  done

  if [[ ${#missing[@]} -gt 0 ]]; then
    hm_log_warn "${#missing[@]} object(s) that a generation needs are missing from the store."
    hm_log_warn "Restore them from a backup, the generations cannot be materialized without them."
  fi

  if [[ ${#objects[@]} -eq 0 && ${#rows[@]} -eq 0 ]]; then
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
      return 0
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
  if [[ ${#rows[@]} -gt 0 ]]; then
    {
      printf 'DELETE FROM files WHERE id IN ('
      local first=1
      for id in "${rows[@]}"; do
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

  hm_log_success "Removed $removed object(s) and ${#rows[@]} database row(s)."

  return 0
}
