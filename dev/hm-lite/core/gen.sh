#!/usr/bin/env bash
#
# core/gen.sh - the gen command.
#
# Captures the content of the pending paths and records the result as a new
# generation.
#
# A generation is a complete snapshot of the tracked paths:
#   * a pending path is captured now, its bytes are hashed, the content is
#     stored and the path is recorded together with its metadata,
#   * every other tracked path carries the content of the parent generation
#     forward,
#   * a tracked path that no longer exists is dropped from the snapshot.
#
# The command is transactional. The generation, its entries and the clearing
# of the pending set are written in a single transaction, therefore a failure
# leaves the project exactly as it was.
#
# The module only defines the gen function. Sourcing it does not run the
# command.
#

# --- Helpers ---------------------------------------------------------------

# _gen_stat FILE
# Print the metadata of FILE as "mode uid gid mtime size". The mode is
# converted into its decimal representation, the database stores it that way.
_gen_stat() {
  local file="$1"
  local octal mode uid gid mtime size

  octal="$(stat -c '%a' -- "$file" 2>/dev/null)" || return 1
  uid="$(stat -c '%u' -- "$file" 2>/dev/null)" || return 1
  gid="$(stat -c '%g' -- "$file" 2>/dev/null)" || return 1
  mtime="$(stat -c '%Y' -- "$file" 2>/dev/null)" || return 1
  size="$(stat -c '%s' -- "$file" 2>/dev/null)" || return 1
  mode="$(hm_mode_to_decimal "$octal")" || return 1

  printf '%s %s %s %s %s\n' "$mode" "$uid" "$gid" "$mtime" "$size"
}

# _gen_cleanup_stage
# Remove the staging directory of the running generation. The function is
# registered as an exit handler, a failed run therefore never leaves a
# temporary copy behind.
_gen_cleanup_stage() {
  local stage="${_GEN_STAGE:-}"

  trap - EXIT
  _GEN_STAGE=""

  [[ -n "$stage" ]] || return 0
  hm_rm_rf_under "${HM_TMP_DIR:-/nonexistent}" "$stage" 2>/dev/null || true
  return 0
}

# _gen_usage
_gen_usage() {
  cat <<'EOF'
Usage: hm gen [options]

Create a new generation from the pending paths of a profile.

Options:
  --profile NAME     Use the profile (default: the active profile, then default)
  --name NAME        Give the generation a name
  --comment TEXT     Attach a comment to the generation
  --yes, -y          Do not ask for a confirmation
  -h, --help         Show this help
EOF
}

# --- The command -----------------------------------------------------------

# gen - capture the pending paths into a new generation.
gen() {
  local name="" comment=""
  local profile_arg="" profile profile_id
  local assume_yes=0
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
      --name)
        [[ $# -ge 2 ]] || hm_die "$HM_EX_USAGE" "--name requires a value."
        name="$2"
        shift 2
        ;;
      --name=*)
        name="${argument#*=}"
        shift
        ;;
      --comment)
        [[ $# -ge 2 ]] || hm_die "$HM_EX_USAGE" "--comment requires a value."
        comment="$2"
        shift 2
        ;;
      --comment=*)
        comment="${argument#*=}"
        shift
        ;;
      --yes | -y)
        assume_yes=1
        shift
        ;;
      -h | --help)
        _gen_usage
        return 0
        ;;
      *)
        hm_die "$HM_EX_USAGE" "Unknown option for 'hm gen': $argument"
        ;;
    esac
  done

  hm_require_cmd stat cp sha256sum
  hm_require_initialized
  hm_lock_acquire exclusive

  profile="$(hm_profile_context_name "$profile_arg")" || exit $?
  profile_id="$(hm_profile_require "$profile")" || exit $?
  hm_log_debug "Creating a generation in the profile $profile."

  # --- Read the pending manifest -----------------------------------------
  local -a pend_ids=() pend_paths=() pend_kinds=()
  local rows row pid hexpath kind path

  if ! hm_db_rows "
    SELECT p.id,
           hex(p.path),
           p.kind
      FROM paths p
      JOIN pending_paths pp ON pp.path_id = p.id
     WHERE pp.profile_id = $profile_id
     ORDER BY p.path;" rows; then
    hm_die "$HM_EX_DB" "Cannot read the pending manifest from the database."
  fi

  while IFS= read -r row; do
    [[ -n "$row" ]] || continue
    IFS="$HM_FIELD_SEP" read -r pid hexpath kind <<< "$row"
    hm_hex_decode path "$hexpath"
    pend_ids+=("$pid")
    pend_paths+=("$path")
    pend_kinds+=("$kind")
  done <<< "$rows"

  if [[ ${#pend_paths[@]} -eq 0 ]]; then
    hm_log_info "There are no pending paths in the profile $profile, nothing to capture."
    return 0
  fi

  # --- Validate the manifest ----------------------------------------------
  # A pending path that vanished or that turned into a symbolic link makes
  # the manifest inconsistent. The generation is refused, the remedy is a
  # new "hm add" run that refreshes the manifest.
  local -a vanished=() unsupported=() outside_root=()
  local profile_root index=0

  profile_root="$(hm_profile_root "$profile")" || exit $?
  for index in "${!pend_paths[@]}"; do
    path="${pend_paths[$index]}"
    if ! hm_path_is_under "$profile_root" "$path"; then
      outside_root+=("$path")
    elif [[ -L "$path" ]]; then
      unsupported+=("$path")
    elif [[ ! -e "$path" ]]; then
      vanished+=("$path")
    fi
  done

  if [[ ${#outside_root[@]} -gt 0 ]]; then
    local outside_path
    hm_log_error "The pending manifest is outside of the profile root, no generation was created."
    for outside_path in "${outside_root[@]}"; do
      hm_log_error "  the path is outside of $profile_root: $(hm_path_display "$outside_path")"
    done
    hm_die "$HM_EX_VALIDATION" "The pending manifest does not belong to the profile $profile."
  fi

  if [[ ${#vanished[@]} -gt 0 || ${#unsupported[@]} -gt 0 ]]; then
    hm_log_error "The pending manifest is inconsistent, no generation was created."
    local broken
    for broken in "${vanished[@]}"; do
      hm_log_error "  the path does not exist any more: $(hm_path_display "$broken")"
    done
    for broken in "${unsupported[@]}"; do
      hm_log_error "  the path is a symbolic link and cannot be captured: $(hm_path_display "$broken")"
    done
    hm_log_error "Run 'hm add <path>' again to refresh the manifest."
    hm_die "$HM_EX_STATE" "The pending manifest is inconsistent."
  fi

  # --- Parent generation --------------------------------------------------
  local parent_id=""
  parent_id="$(hm_gen_latest "$profile")"
  [[ -n "$parent_id" ]] && parent_id="$(hm_sql_int "$parent_id")"

  # --- Capture the pending content ----------------------------------------
  local stage
  stage="$(hm_mktemp_dir "gen.XXXXXXXX")" || hm_die "$HM_EX_IO" "Cannot create the staging directory."
  _GEN_STAGE="$stage"
  trap '_gen_cleanup_stage' EXIT

  local -A hashes=() modes=() uids=() gids=() mtimes=() sizes=()
  local new_objects=0 reused_objects=0 captured=0
  local hash mode uid gid mtime size before after staged

  for index in "${!pend_paths[@]}"; do
    path="${pend_paths[$index]}"
    kind="${pend_kinds[$index]}"

    if [[ "$kind" == "dir" ]]; then
      if ! read -r mode uid gid mtime size <<< "$(_gen_stat "$path")"; then
        hm_die "$HM_EX_IO" "Cannot read the metadata of: $(hm_path_display "$path")"
      fi
      hashes["$index"]=""
      modes["$index"]="$mode"
      uids["$index"]="$uid"
      gids["$index"]="$gid"
      mtimes["$index"]="$mtime"
      sizes["$index"]=0
      captured=$((captured + 1))
      continue
    fi

    # A regular file is copied first, the hash is calculated from the copy.
    # The stored object therefore always matches the recorded hash, even
    # when the source changes while it is read.
    staged="$stage/object.$index"
    before="$(stat -c '%Y:%s' -- "$path" 2>/dev/null)" || hm_die "$HM_EX_IO" "Cannot read: $(hm_path_display "$path")"

    if ! cp --preserve=mode,timestamps -- "$path" "$staged"; then
      hm_die "$HM_EX_IO" "Cannot read the file: $(hm_path_display "$path")"
    fi

    after="$(stat -c '%Y:%s' -- "$path" 2>/dev/null || true)"
    if [[ "$before" != "$after" ]]; then
      hm_log_warn "The file changed while it was captured: $(hm_path_display "$path")"
    fi

    hash="$(hm_sha256_file "$staged")" || hm_die "$HM_EX_STORE" "Cannot hash the file: $(hm_path_display "$path")"
    if ! hm_is_sha256 "$hash"; then
      hm_die "$HM_EX_STORE" "The hash of the file is not a valid SHA-256 value: $(hm_path_display "$path")"
    fi

    # The metadata is read from the copy, the ownership from the source.
    if ! read -r mode uid gid mtime size <<< "$(_gen_stat "$staged")"; then
      hm_die "$HM_EX_IO" "Cannot read the metadata of the captured file."
    fi
    uids["$index"]="$(stat -c '%u' -- "$path" 2>/dev/null || printf '0')"
    gids["$index"]="$(stat -c '%g' -- "$path" 2>/dev/null || printf '0')"

    if hm_store_has "$hash"; then
      reused_objects=$((reused_objects + 1))
    else
      new_objects=$((new_objects + 1))
    fi

    hm_store_put "$staged" "$hash"

    hashes["$index"]="$hash"
    modes["$index"]="$mode"
    mtimes["$index"]="$mtime"
    sizes["$index"]="$size"
    captured=$((captured + 1))
  done

  # --- The paths that are carried forward ---------------------------------
  local -a dropped_ids=()
  local carried=0

  if [[ -n "$parent_id" ]]; then
    if ! hm_db_rows "
      SELECT ge.path_id,
             hex(p.path),
             ge.entry_type,
             COALESCE(ge.file_id, 0),
             ge.mode,
             ge.owner_uid,
             ge.group_gid,
             ge.mtime,
             ge.size
        FROM generation_entries ge
        JOIN paths p ON p.id = ge.path_id
       WHERE ge.generation_id = $parent_id
       ORDER BY p.path;" rows; then
      hm_die "$HM_EX_DB" "Cannot read the parent generation from the database."
    fi

    while IFS= read -r row; do
      [[ -n "$row" ]] || continue
      IFS="$HM_FIELD_SEP" read -r pid hexpath kind _file_id _mode _uid _gid _mtime _size <<< "$row"
      hm_hex_decode path "$hexpath"

      # A pending path is captured above, the SQL statement excludes it as
      # well. The check keeps the preview honest.
      local is_pending=0
      local pending_index
      for pending_index in "${!pend_paths[@]}"; do
        if [[ "${pend_paths[$pending_index]}" == "$path" ]]; then
          is_pending=1
          break
        fi
      done
      [[ $is_pending -eq 0 ]] || continue

      if [[ -e "$path" ]]; then
        carried=$((carried + 1))
      else
        dropped_ids+=("$pid")
      fi
    done <<< "$rows"
  fi

  # --- Preview -------------------------------------------------------------
  printf '%sGeneration preview (profile: %s)%s\n' \
    "$HM_C_OUT_HEADING" "$profile" "$HM_C_OUT_RESET"
  printf '\n'
  printf '  %d path(s) captured\n' "$captured"
  printf '  %d new content object(s)\n' "$new_objects"
  printf '  %d content object(s) reused\n' "$reused_objects"
  printf '  %d path(s) carried forward\n' "$carried"
  printf '  %d path(s) dropped, they no longer exist\n' "${#dropped_ids[@]}"
  printf '\n'

  printf '%sCaptured paths:%s\n' "$HM_C_OUT_HEADING" "$HM_C_OUT_RESET"
  for index in "${!pend_paths[@]}"; do
    printf '  %s\n' "$(hm_path_display "${pend_paths[$index]}")"
  done
  printf '\n'

  if [[ $assume_yes -eq 0 ]]; then
    if ! hm_confirm "Create the generation? [y/N]"; then
      hm_log_info "Cancelled, nothing was changed."
      return "$HM_EX_DECLINED"
    fi
  fi

  # --- Write the generation -----------------------------------------------
  local now
  now="$(hm_now_epoch)"

  {
    # The context table carries the identifier of the new generation.
    printf 'CREATE TEMP TABLE IF NOT EXISTS _hm_gen_ctx (id INTEGER);\n'
    printf 'DELETE FROM _hm_gen_ctx;\n'

    if [[ -n "$parent_id" ]]; then
      printf 'INSERT INTO generations (number, name, comment, created_at, parent_id, profile_id) VALUES ((SELECT next_generation_number FROM profiles WHERE id = %s), %s, %s, %s, %s, %s);\n' \
        "$profile_id" "$(hm_sql_quote "$name")" "$(hm_sql_quote "$comment")" "$now" "$parent_id" "$profile_id"
    else
      printf 'INSERT INTO generations (number, name, comment, created_at, parent_id, profile_id) VALUES ((SELECT next_generation_number FROM profiles WHERE id = %s), %s, %s, %s, NULL, %s);\n' \
        "$profile_id" "$(hm_sql_quote "$name")" "$(hm_sql_quote "$comment")" "$now" "$profile_id"
    fi
    printf 'INSERT INTO _hm_gen_ctx (id) VALUES (last_insert_rowid());\n'
    printf 'UPDATE profiles SET next_generation_number = next_generation_number + 1 WHERE id = %s;\n' \
      "$profile_id"

    # The content objects.
    for index in "${!pend_paths[@]}"; do
      hash="${hashes[$index]}"
      [[ -n "$hash" ]] || continue
      printf 'INSERT OR IGNORE INTO files (hash, size, created_at) VALUES (%s, %s, %s);\n' \
        "$(hm_sql_quote "$hash")" "${sizes[$index]}" "$now"
    done

    # The captured paths.
    for index in "${!pend_paths[@]}"; do
      hash="${hashes[$index]}"
      if [[ -n "$hash" ]]; then
        printf 'INSERT INTO generation_entries (generation_id, path_id, file_id, entry_type, mode, owner_uid, group_gid, mtime, size) VALUES ((SELECT id FROM _hm_gen_ctx), %s, (SELECT id FROM files WHERE hash = %s), %s, %s, %s, %s, %s, %s);\n' \
          "${pend_ids[$index]}" "$(hm_sql_quote "$hash")" \
          "$(hm_sql_quote "${pend_kinds[$index]}")" \
          "${modes[$index]}" "${uids[$index]}" "${gids[$index]}" "${mtimes[$index]}" "${sizes[$index]}"
      else
        printf 'INSERT INTO generation_entries (generation_id, path_id, file_id, entry_type, mode, owner_uid, group_gid, mtime, size) VALUES ((SELECT id FROM _hm_gen_ctx), %s, NULL, %s, %s, %s, %s, %s, %s);\n' \
          "${pend_ids[$index]}" \
          "$(hm_sql_quote "${pend_kinds[$index]}")" \
          "${modes[$index]}" "${uids[$index]}" "${gids[$index]}" "${mtimes[$index]}" "${sizes[$index]}"
      fi
    done

    # The paths that are carried forward from the parent generation.
    if [[ -n "$parent_id" ]]; then
      printf 'INSERT INTO generation_entries (generation_id, path_id, file_id, entry_type, mode, owner_uid, group_gid, mtime, size) SELECT (SELECT id FROM _hm_gen_ctx), ge.path_id, ge.file_id, ge.entry_type, ge.mode, ge.owner_uid, ge.group_gid, ge.mtime, ge.size FROM generation_entries ge WHERE ge.generation_id = %s AND ge.path_id NOT IN (SELECT path_id FROM pending_paths WHERE profile_id = %s)' \
        "$parent_id" "$profile_id"
      if [[ ${#dropped_ids[@]} -gt 0 ]]; then
        printf ' AND ge.path_id NOT IN (%s)' "$(IFS=,; printf '%s' "${dropped_ids[*]}")"
      fi
      printf ';\n'
    fi

    # The pending set of the profile is cleared in the same transaction as
    # the generation.
    printf 'DELETE FROM pending_paths WHERE profile_id = %s;\n' "$profile_id"
  } | hm_db_tx || hm_die "$HM_EX_DB" "The generation failed, nothing was changed."

  local generation_id generation_number parent_number
  generation_id="$(hm_gen_latest "$profile")"
  generation_number="$(hm_gen_number "$generation_id")"

  hm_log_success "Created generation $generation_number in the profile $profile with $((captured + carried)) entries."
  printf 'Generation: %s%s%s\n' "$HM_C_OUT_GREEN" "$generation_number" "$HM_C_OUT_RESET"
  printf 'Profile:    %s%s%s\n' "$HM_C_OUT_CYAN" "$profile" "$HM_C_OUT_RESET"
  if [[ -n "$parent_id" ]]; then
    parent_number="$(hm_gen_number "$parent_id")"
    printf 'Parent:     %s%s%s\n' "$HM_C_OUT_CYAN" "$parent_number" "$HM_C_OUT_RESET"
  fi

  return 0
}
