#!/usr/bin/env bash
#
# core/delete.sh - the delete command.
#
# Removes one generation and its entries. The generation is previewed and
# the removal needs a confirmation, "--yes" skips the prompt.
#
# The selected generation is never deleted, "hm switch" must point to
# another generation first. The content objects that no other generation
# uses stay in the store until "hm clean" runs, the command reports how
# many objects that affects.
#
# The removal runs in a single transaction. The foreign key clears the
# parent of the child generations and the entry delete comes first, so a
# failure leaves the project exactly as it was.
#
# The module only defines the delete function. Sourcing it does not run
# the command.
#

# --- Helpers ---------------------------------------------------------------

# _delete_usage
_delete_usage() {
  cat <<'EOF'
Usage: hm delete <generation> [options]

Delete a generation and its entries.

Options:
  --yes, -y     Do not ask for a confirmation
  -h, --help    Show this help
EOF
}

# --- The command -----------------------------------------------------------

# delete - remove a generation that is not selected.
delete() {
  local generation=""
  local assume_yes=0
  local argument
  local id selected row name_hex name created entries objects orphans

  while [[ $# -gt 0 ]]; do
    argument="$1"
    case "$argument" in
      --yes | -y)
        assume_yes=1
        shift
        ;;
      -h | --help)
        _delete_usage
        return 0
        ;;
      -*)
        hm_die "$HM_EX_USAGE" "Unknown option for 'hm delete': $argument"
        ;;
      *)
        [[ -z "$generation" ]] || hm_die "$HM_EX_USAGE" "Usage: hm delete <generation> [options]"
        generation="$argument"
        shift
        ;;
    esac
  done

  [[ -n "$generation" ]] || hm_die "$HM_EX_USAGE" "Usage: hm delete <generation> [options]"

  hm_require_initialized
  hm_lock_acquire exclusive

  if ! hm_gen_exists "$generation"; then
    hm_die "$HM_EX_STATE" "There is no generation with the id $generation."
  fi

  id="$(hm_sql_int "$generation")"
  selected="$(hm_gen_selected)"

  if [[ -n "$selected" && "$id" -eq "$selected" ]]; then
    hm_die "$HM_EX_VALIDATION" "The generation $generation is the selected generation, switch to another generation before deleting it."
  fi

  if ! hm_db_rows "
    SELECT hex(COALESCE(name, '')), created_at
      FROM generations
     WHERE id = $id;" row; then
    hm_die "$HM_EX_DB" "Cannot read the generation $generation from the database."
  fi

  [[ -n "$row" ]] || hm_die "$HM_EX_STATE" "There is no generation with the id $generation."
  IFS="$HM_FIELD_SEP" read -r name_hex created <<< "$row"
  hm_hex_decode name "$name_hex"

  entries="$(hm_gen_entry_count "$generation")" ||
    hm_die "$HM_EX_DB" "Cannot read the entries of the generation $generation from the database."
  objects="$(hm_gen_object_count "$generation")" ||
    hm_die "$HM_EX_DB" "Cannot read the content objects of the generation $generation from the database."

  orphans="$(hm_db_scalar "
    SELECT COUNT(DISTINCT ge.file_id)
      FROM generation_entries ge
     WHERE ge.generation_id = $id
       AND ge.file_id IS NOT NULL
       AND NOT EXISTS (SELECT 1
                         FROM generation_entries other
                        WHERE other.file_id = ge.file_id
                          AND other.generation_id <> $id);")" ||
    hm_die "$HM_EX_DB" "Cannot read the content objects of the generation $generation from the database."

  hm_log_debug "Deleting the generation $generation."

  printf '%sDelete preview:%s\n' "$HM_C_OUT_BOLD" "$HM_C_OUT_RESET"
  printf '\n'
  printf '  %-11s %s%s%s\n' "Generation:" "$HM_C_OUT_CYAN" "$id" "$HM_C_OUT_RESET"
  printf '  %-11s %s\n' "Name:" "${name:--}"
  printf '  %-11s %s\n' "Created:" "$(hm_format_epoch "$created" || printf '%s' "$created")"
  printf '  %-11s %s\n' "Entries:" "$entries"
  printf '  %-11s %s\n' "Objects:" "$objects"
  printf '\n'

  if [[ "$orphans" -gt 0 ]]; then
    printf '  %s%s content object(s) are used by no other generation.%s\n' \
      "$HM_C_OUT_YELLOW" "$orphans" "$HM_C_OUT_RESET"
    printf '  They stay in the store until "hm clean" runs.\n'
    printf '\n'
  fi

  if [[ $assume_yes -eq 0 ]]; then
    if ! hm_confirm "Delete the generation? [y/N]"; then
      hm_log_info "Cancelled, nothing was deleted."
      return "$HM_EX_DECLINED"
    fi
  fi

  {
    printf 'DELETE FROM generation_entries WHERE generation_id = %s;\n' "$id"
    printf 'DELETE FROM generations WHERE id = %s;\n' "$id"
  } | hm_db_tx || hm_die "$HM_EX_DB" "Cannot delete the generation, nothing was changed."

  hm_log_success "Deleted the generation $generation."

  if [[ "$orphans" -gt 0 ]]; then
    hm_log_info "$orphans content object(s) are no longer referenced, run 'hm clean' to remove them."
  fi

  return 0
}
