#!/usr/bin/env bash
#
# core/show.sh - the show command.
#
# Read only view of a single generation: its metadata and its entries.
# The command never changes anything, it therefore only takes a shared
# lock.
#
# The entry table is the detailed variant of "hm list --generation": it
# adds the owner, the group and the modification time. Both commands read
# the entries through the shared hm_gen_entries helper, the query exists
# once.
#
# The module only defines the show function. Sourcing it does not run the
# command.
#

# --- Helpers ---------------------------------------------------------------

# _show_usage
_show_usage() {
  cat <<'EOF'
Usage: hm show [--profile NAME] <generation>

Show the metadata and the entries of a generation.

Options:
  --profile NAME  Require the generation to belong to the profile
  -h, --help      Show this help
EOF
}

# _show_generation GENERATION - print the metadata and the entries.
_show_generation() {
  local generation="$1" id
  local row name_hex comment_hex name comment profile_name created parent
  local entries objects size selected status missing missing_count=0
  local rows encoded entry_type hash_hex mode uid gid mtime entry_size path hash

  id="$(hm_sql_int "$generation")"

  if ! hm_db_rows "
    SELECT hex(COALESCE(g.name, '')),
           hex(COALESCE(g.comment, '')),
           pr.name,
           g.created_at,
           COALESCE(g.parent_id, ''),
           (SELECT COUNT(*) FROM generation_entries ge WHERE ge.generation_id = g.id),
           (SELECT COUNT(DISTINCT ge.file_id) FROM generation_entries ge WHERE ge.generation_id = g.id AND ge.file_id IS NOT NULL),
           (SELECT COALESCE(SUM(ge.size), 0) FROM generation_entries ge WHERE ge.generation_id = g.id)
      FROM generations g
      JOIN profiles pr ON pr.id = g.profile_id
     WHERE g.id = $id;" row; then
    hm_die "$HM_EX_DB" "Cannot read the generation $generation from the database."
  fi

  [[ -n "$row" ]] || hm_die "$HM_EX_DB" "Cannot read the generation $generation from the database."
  IFS="$HM_FIELD_SEP" read -r name_hex comment_hex profile_name created parent entries objects size <<< "$row"

  hm_hex_decode name "$name_hex"
  hm_hex_decode comment "$comment_hex"

  selected="$(hm_gen_selected "$profile_name")"
  status="no"
  if [[ -n "$selected" && "$id" -eq "$selected" ]]; then
    status="yes"
  fi

  if ! hm_gen_missing_objects "$generation" missing; then
    hm_die "$HM_EX_DB" "Cannot verify the content objects of the generation $generation."
  fi

  while IFS= read -r hash; do
    [[ -n "$hash" ]] && missing_count=$((missing_count + 1))
  done <<< "$missing"

  printf '%sGeneration %s%s\n' "$HM_C_OUT_HEADING" "$id" "$HM_C_OUT_RESET"
  printf '\n'
  printf '  %s%-11s %s%s\n' "$HM_C_OUT_LABEL" "Name:" "${name:--}" "$HM_C_OUT_RESET"
  printf '  %s%-11s %s%s\n' "$HM_C_OUT_LABEL" "Comment:" "${comment:--}" "$HM_C_OUT_RESET"
  printf '  %s%-11s %s%s\n' "$HM_C_OUT_LABEL" "Profile:" "$profile_name" "$HM_C_OUT_RESET"
  printf '  %s%-11s %s%s\n' "$HM_C_OUT_LABEL" "Created:" "$(hm_format_epoch "$created" || printf '%s' "$created")" "$HM_C_OUT_RESET"
  printf '  %s%-11s %s%s\n' "$HM_C_OUT_LABEL" "Parent:" "${parent:--}" "$HM_C_OUT_RESET"
  printf '  %s%-11s %s%s\n' "$HM_C_OUT_LABEL" "Selected:" "$status" "$HM_C_OUT_RESET"
  printf '  %s%-11s %s%s\n' "$HM_C_OUT_LABEL" "Entries:" "$entries" "$HM_C_OUT_RESET"
  printf '  %s%-11s %s%s\n' "$HM_C_OUT_LABEL" "Objects:" "$objects" "$HM_C_OUT_RESET"
  printf '  %s%-11s %s%s\n' "$HM_C_OUT_LABEL" "Size:" "$size bytes" "$HM_C_OUT_RESET"
  if [[ "$missing_count" -gt 0 ]]; then
    printf '  %s%-11s %s%s\n' "$HM_C_OUT_LABEL" "Missing:" "$missing_count content object(s)" "$HM_C_OUT_RESET"
  fi
  printf '\n'

  if ! hm_gen_entries "$generation" rows; then
    hm_die "$HM_EX_DB" "Cannot read the entries of the generation $generation."
  fi

  printf '%s%-40s %-5s %-5s %-9s %10s  %-19s %s%s\n' \
    "$HM_C_OUT_HEADING" "PATH" "TYPE" "MODE" "OWNER" "SIZE" "MODIFIED" "HASH" "$HM_C_OUT_RESET"

  while IFS= read -r row; do
    [[ -n "$row" ]] || continue
    IFS="$HM_FIELD_SEP" read -r encoded entry_type hash_hex mode uid gid mtime entry_size <<< "$row"

    hm_hex_decode path "$encoded"
    hm_hex_decode hash "$hash_hex"

    if [[ -z "$hash" ]]; then
      hash="-"
    else
      hash="${hash:0:12}"
    fi

    printf '%s%-40s%s %-5s %-5s %-9s %10s  %-19s %s\n' \
      "$HM_C_OUT_CYAN" "$(hm_path_display "$path")" "$HM_C_OUT_RESET" "$entry_type" \
      "$(hm_mode_to_octal "$mode" || printf '%s' "$mode")" \
      "$uid:$gid" "$entry_size" \
      "$(hm_format_epoch "$mtime" || printf '%s' "$mtime")" "$hash"
  done <<< "$rows"

  if [[ "$missing_count" -gt 0 ]]; then
    hm_log_warn "$missing_count content object(s) of the generation $generation are missing from the store."
  fi
}

# --- The command -----------------------------------------------------------

# show - print a generation and its entries.
show() {
  local generation="" profile_arg="" profile
  local argument

  while [[ $# -gt 0 ]]; do
    argument="$1"
    case "$argument" in
      --profile)
        [[ $# -ge 2 ]] || hm_die "$HM_EX_USAGE" "--profile requires a value."
        profile_arg="$2"
        shift 2
        ;;
      --profile=*)
        profile_arg="${argument#*=}"
        shift
        ;;
      -h | --help)
        _show_usage
        return 0
        ;;
      -*)
        hm_die "$HM_EX_USAGE" "Unknown option for 'hm show': $argument"
        ;;
      *)
        [[ -z "$generation" ]] || hm_die "$HM_EX_USAGE" "Usage: hm show [--profile NAME] <generation>"
        generation="$argument"
        shift
        ;;
    esac
  done

  [[ -n "$generation" ]] || hm_die "$HM_EX_USAGE" "Usage: hm show [--profile NAME] <generation>"

  hm_require_initialized
  hm_lock_acquire shared

  profile="$(hm_profile_scope "$profile_arg")"
  if [[ -n "$profile" ]]; then
    hm_profile_require "$profile" > /dev/null
  fi

  if ! hm_gen_exists "$generation"; then
    hm_die "$HM_EX_STATE" "There is no generation with the id $generation."
  fi

  if [[ -n "$profile" && "$(hm_profile_of_generation "$generation")" != "$profile" ]]; then
    hm_die "$HM_EX_VALIDATION" "The generation $generation does not belong to the profile $profile."
  fi

  hm_log_debug "Showing the generation $generation."
  _show_generation "$generation"

  return 0
}
