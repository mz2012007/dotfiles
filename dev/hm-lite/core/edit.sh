#!/usr/bin/env bash
#
# core/edit.sh - the edit command.
#
# Changes the name and the comment of an existing generation. The entries of
# a generation are immutable, the metadata is not: the name and the comment
# are labels for the human reader.
#
# The command changes the database only. It takes an exclusive lock, previews
# the old and the new values and asks for a confirmation, "--yes" skips the
# prompt. The update runs in a single transaction.
#
# The module only defines the edit function. Sourcing it does not run the
# command.
#

# --- Helpers ---------------------------------------------------------------

# _edit_usage
_edit_usage() {
  cat <<'EOF'
Usage: hm edit <generation> [options]

Change the name and the comment of an existing generation.

Options:
  --name NAME        Set the name of the generation
  --comment TEXT     Set the comment of the generation
  --clear-name       Remove the name of the generation
  --clear-comment    Remove the comment of the generation
  --yes, -y          Do not ask for a confirmation
  -h, --help         Show this help
EOF
}

# --- The command -----------------------------------------------------------

# edit GENERATION [OPTIONS] - change the metadata of a generation.
edit() {
  local generation=""
  local name="" comment=""
  local have_name=0 have_comment=0
  local clear_name=0 clear_comment=0
  local assume_yes=0
  local argument

  while [[ $# -gt 0 ]]; do
    argument="$1"
    case "$argument" in
      --name)
        [[ $# -ge 2 ]] || hm_die "$HM_EX_USAGE" "--name requires a value."
        name="$2"
        have_name=1
        shift 2
        ;;
      --name=*)
        name="${argument#*=}"
        have_name=1
        shift
        ;;
      --comment)
        [[ $# -ge 2 ]] || hm_die "$HM_EX_USAGE" "--comment requires a value."
        comment="$2"
        have_comment=1
        shift 2
        ;;
      --comment=*)
        comment="${argument#*=}"
        have_comment=1
        shift
        ;;
      --clear-name)
        clear_name=1
        shift
        ;;
      --clear-comment)
        clear_comment=1
        shift
        ;;
      --yes | -y)
        assume_yes=1
        shift
        ;;
      -h | --help)
        _edit_usage
        return 0
        ;;
      -*)
        hm_die "$HM_EX_USAGE" "Unknown option for 'hm edit': $argument"
        ;;
      *)
        if [[ -n "$generation" ]]; then
          hm_die "$HM_EX_USAGE" "Usage: hm edit <generation> [options]"
        fi
        generation="$argument"
        shift
        ;;
    esac
  done

  if [[ -z "$generation" ]]; then
    hm_die "$HM_EX_USAGE" "Usage: hm edit <generation> [options]"
  fi

  if (( have_name + have_comment + clear_name + clear_comment == 0 )); then
    hm_die "$HM_EX_USAGE" "At least one of --name, --comment, --clear-name or --clear-comment is required."
  fi

  if (( have_name + clear_name > 1 )); then
    hm_die "$HM_EX_USAGE" "--name and --clear-name cannot be used together."
  fi

  if (( have_comment + clear_comment > 1 )); then
    hm_die "$HM_EX_USAGE" "--comment and --clear-comment cannot be used together."
  fi

  if (( have_name )) && [[ -z "$name" ]]; then
    hm_die "$HM_EX_USAGE" "--name requires a non-empty value, use --clear-name to remove the name."
  fi

  if (( have_comment )) && [[ -z "$comment" ]]; then
    hm_die "$HM_EX_USAGE" "--comment requires a non-empty value, use --clear-comment to remove the comment."
  fi

  hm_require_initialized
  hm_lock_acquire exclusive

  if ! hm_gen_exists "$generation"; then
    hm_die "$HM_EX_STATE" "There is no generation with the id $generation."
  fi

  local id
  id="$(hm_sql_int "$generation")"

  # --- Read the current metadata ------------------------------------------
  local rows
  local current_name_hex current_comment_hex name_is_null comment_is_null
  local current_name current_comment

  if ! hm_db_rows "
    SELECT hex(COALESCE(g.name, '')),
           (g.name IS NULL),
           hex(COALESCE(g.comment, '')),
           (g.comment IS NULL)
      FROM generations g
     WHERE g.id = $id;" rows; then
    hm_die "$HM_EX_DB" "Cannot read the generation $generation from the database."
  fi

  [[ -n "$rows" ]] || hm_die "$HM_EX_STATE" "There is no generation with the id $generation."

  IFS="$HM_FIELD_SEP" read -r current_name_hex name_is_null \
    current_comment_hex comment_is_null <<< "$rows"
  hm_hex_decode current_name "$current_name_hex"
  hm_hex_decode current_comment "$current_comment_hex"

  # --- Compute the new values ---------------------------------------------
  local old_name old_comment new_name new_comment
  local name_sql comment_sql

  if [[ "$name_is_null" == "1" ]]; then
    old_name="-"
  else
    old_name="${current_name:--}"
  fi

  if [[ "$comment_is_null" == "1" ]]; then
    old_comment="-"
  else
    old_comment="${current_comment:--}"
  fi

  if (( clear_name )); then
    name_sql="NULL"
    new_name="-"
  elif (( have_name )); then
    name_sql="$(hm_sql_quote "$name")"
    new_name="$name"
  elif [[ "$name_is_null" == "1" ]]; then
    name_sql="NULL"
    new_name="-"
  else
    name_sql="$(hm_sql_quote "$current_name")"
    new_name="$old_name"
  fi

  if (( clear_comment )); then
    comment_sql="NULL"
    new_comment="-"
  elif (( have_comment )); then
    comment_sql="$(hm_sql_quote "$comment")"
    new_comment="$comment"
  elif [[ "$comment_is_null" == "1" ]]; then
    comment_sql="NULL"
    new_comment="-"
  else
    comment_sql="$(hm_sql_quote "$current_comment")"
    new_comment="$old_comment"
  fi

  # --- Preview -------------------------------------------------------------
  printf '%sEdit preview for generation %s%s%s\n' \
    "$HM_C_OUT_BOLD" "$HM_C_OUT_CYAN" "$id" "$HM_C_OUT_RESET"
  printf '\n'
  printf '  %s%-11s%s %s\n' "$HM_C_OUT_BOLD" "Generation:" "$HM_C_OUT_RESET" "$id"

  if [[ "$old_name" == "$new_name" ]]; then
    printf '  %s%-11s%s %s\n' "$HM_C_OUT_BOLD" "Name:" "$HM_C_OUT_RESET" "$new_name"
  else
    printf '  %s%-11s%s %s -> %s%s%s\n' "$HM_C_OUT_BOLD" "Name:" "$HM_C_OUT_RESET" \
      "$old_name" "$HM_C_OUT_GREEN" "$new_name" "$HM_C_OUT_RESET"
  fi

  if [[ "$old_comment" == "$new_comment" ]]; then
    printf '  %s%-11s%s %s\n' "$HM_C_OUT_BOLD" "Comment:" "$HM_C_OUT_RESET" "$new_comment"
  else
    printf '  %s%-11s%s %s -> %s%s%s\n' "$HM_C_OUT_BOLD" "Comment:" "$HM_C_OUT_RESET" \
      "$old_comment" "$HM_C_OUT_GREEN" "$new_comment" "$HM_C_OUT_RESET"
  fi
  printf '\n'

  if [[ $assume_yes -eq 0 ]]; then
    if ! hm_confirm "Apply the change? [y/N]"; then
      hm_log_info "Cancelled, nothing was changed."
      return "$HM_EX_DECLINED"
    fi
  fi

  # --- Update the metadata -------------------------------------------------
  hm_log_debug "Updating the metadata of the generation $id."

  {
    printf 'UPDATE generations SET name = %s, comment = %s WHERE id = %s;\n' \
      "$name_sql" "$comment_sql" "$id"
  } | hm_db_tx || hm_die "$HM_EX_DB" "Cannot update the generation, nothing was changed."

  hm_log_success "Updated the generation $generation."

  return 0
}
