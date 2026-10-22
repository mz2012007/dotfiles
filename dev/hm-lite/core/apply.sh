#!/usr/bin/env bash
#
# core/apply.sh - the apply command.
#
# Writes the content of a generation to the live filesystem.
#
# The command is the only one that touches files outside of the project
# directory, therefore it is the most defensive one:
#
#   * it never escalates privileges, it never runs sudo,
#   * it writes only to the absolute paths that the generation records,
#   * it refuses a path that is a symbolic link, it never writes through a
#     link and it never replaces a link silently,
#   * it refuses a path where the type does not match the generation,
#   * it refuses a path outside of the home directory unless the
#     configuration allows it,
#   * it backs up every file it overwrites and writes a manifest,
#   * it verifies every file it wrote and rolls the whole operation back
#     when a verification fails,
#   * it asks for a confirmation before it changes anything.
#

# --- Helpers ---------------------------------------------------------------

# _apply_usage
_apply_usage() {
  cat <<'EOF'
Usage: hm apply [generation] [options]

Write a generation to the live filesystem.

Without an argument the selected generation is applied.

Options:
  --dry-run      Show the preview only, change nothing
  --yes, -y      Do not ask for a confirmation
  -h, --help     Show this help
EOF
}

# _apply_backup_dir - create the backup directory of this run.
_apply_backup_dir() {
  local dir

  dir="$HM_BACKUP_DIR/apply-$(hm_utc_stamp)-$$"
  if ! mkdir -p -- "$dir/files"; then
    hm_die "$HM_EX_IO" "Cannot create the backup directory: $(hm_path_display "$dir")"
  fi
  chmod 700 -- "$dir" 2>/dev/null || true

  printf '%s\n' "$dir"
}

# _apply_missing_ancestor PATH
# Print the highest directory that has to be created for PATH, or nothing
# when the parent of PATH already exists.
_apply_missing_ancestor() {
  local path="$1" parent

  parent="${path%/*}"
  [[ "$parent" == "$path" ]] && return 0
  [[ -n "$parent" ]] || return 0

  while [[ -n "$parent" && "$parent" != "/" && ! -e "$parent" ]]; do
    parent="${parent%/*}"
  done

  [[ -d "$parent" ]] || return 0
  [[ "$parent" == "/" ]] && return 0

  printf '%s\n' "$parent"
}

# _apply_restore FILE TARGET MODE
# Put FILE back to TARGET, atomically.
_apply_restore() {
  local source="$1" target="$2" mode="$3"
  local dir tmp

  dir="${target%/*}"
  [[ "$dir" == "$target" ]] && dir="/"

  tmp="$dir/.hm-restore.$$.tmp"
  if ! cp -- "$source" "$tmp"; then
    rm -f -- "$tmp" 2>/dev/null || true
    return 1
  fi
  chmod "$mode" -- "$tmp" 2>/dev/null || true
  if ! mv -f -- "$tmp" "$target"; then
    rm -f -- "$tmp" 2>/dev/null || true
    return 1
  fi
  return 0
}

# _apply_rollback MANIFEST BACKUP_DIR
# Undo everything that the manifest describes. The entries are processed in
# reverse order, a child is therefore always removed before its parent.
_apply_rollback() {
  local manifest="$1" backup="$2"
  local line action hexpath backup_name old_mode new_mode path

  while IFS=$'\t' read -r action hexpath backup_name old_mode new_mode; do
    [[ -n "$action" ]] || continue
    hm_hex_decode path "$hexpath"

    case "$action" in
      update)
        if [[ -n "$backup_name" && -f "$backup/files/$backup_name" ]]; then
          if ! _apply_restore "$backup/files/$backup_name" "$path" "$old_mode"; then
            hm_log_error "Cannot restore: $(hm_path_display "$path")"
          fi
        fi
        ;;
      create)
        if [[ -d "$path" && ! -L "$path" ]]; then
          rmdir -- "$path" 2>/dev/null || true
        else
          rm -f -- "$path" 2>/dev/null || true
        fi
        ;;
      mkdir)
        rmdir -- "$path" 2>/dev/null || true
        ;;
      mode)
        chmod "$old_mode" -- "$path" 2>/dev/null || true
        ;;
    esac
  done < <(tac -- "$manifest")

  return 0
}

# --- The command -----------------------------------------------------------

# apply [GENERATION] - write a generation to the live filesystem.
apply() {
  local generation=""
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
        _apply_usage
        return 0
        ;;
      -*)
        hm_die "$HM_EX_USAGE" "Unknown option for 'hm apply': $argument"
        ;;
      *)
        if [[ -n "$generation" ]]; then
          hm_die "$HM_EX_USAGE" "Usage: hm apply [generation]"
        fi
        generation="$argument"
        shift
        ;;
    esac
  done

  hm_require_cmd stat cp sha256sum
  hm_require_initialized
  hm_lock_acquire exclusive

  # --- Resolve the generation ---------------------------------------------
  if [[ -z "$generation" ]]; then
    generation="$(hm_gen_selected 2>/dev/null || true)"
    if [[ -z "$generation" ]]; then
      hm_die "$HM_EX_STATE" "No generation is selected. Run 'hm switch <generation>' or name a generation."
    fi
  fi

  if ! hm_gen_exists "$generation"; then
    hm_die "$HM_EX_STATE" "There is no generation with the id $generation."
  fi

  local missing
  missing="$(hm_gen_missing_objects "$generation")"
  if [[ -n "$missing" ]]; then
    local hash count=0
    while IFS= read -r hash; do
      [[ -n "$hash" ]] || continue
      count=$((count + 1))
    done <<< "$missing"
    hm_log_error "The generation needs $count content object(s) that are missing from the store."
    hm_die "$HM_EX_STORE" "The generation cannot be applied."
  fi

  # --- Classify every entry ------------------------------------------------
  local -A actions=() reasons=() hashes=() octals=()
  local -a order=()
  local create=0 update=0 mode_change=0 unchanged=0 conflict=0
  local allow_outside
  allow_outside="$(hm_config_get HM_ALLOW_OUTSIDE_HOME 0)"

  local row encoded entry_type hash_hex mode uid gid mtime size
  local path hash action reason current_hash current_mode ancestor

  while IFS= read -r row; do
    [[ -n "$row" ]] || continue
    IFS="$HM_FIELD_SEP" read -r encoded entry_type hash_hex mode uid gid mtime size <<< "$row"

    hm_hex_decode path "$encoded"
    hm_hex_decode hash "$hash_hex"

    order+=("$encoded")
    hashes["$encoded"]="$hash"
    octals["$encoded"]="$(hm_mode_to_octal "$mode" || printf '%s' "$mode")"

    action=""
    reason=""

    if ! hm_path_is_safe_target "$path"; then
      action="CONFLICT"
      reason="the path is not a safe destination"
    elif [[ "$allow_outside" != "1" ]] && ! hm_path_in_home "$path"; then
      action="CONFLICT"
      reason="the path is outside of the home directory"
    elif [[ -L "$path" ]]; then
      action="CONFLICT"
      reason="the path is a symbolic link"
    elif [[ "$entry_type" == "dir" ]]; then
      if [[ -e "$path" ]]; then
        if [[ -d "$path" ]]; then
          current_mode="$(stat -c '%a' -- "$path" 2>/dev/null || printf '')"
          if [[ "$current_mode" == "${octals[$encoded]}" ]]; then
            action="UNCHANGED"
          else
            action="MODE"
          fi
        else
          action="CONFLICT"
          reason="a file exists where a directory is expected"
        fi
      else
        action="CREATE"
      fi
    else
      if [[ -e "$path" ]]; then
        if [[ -d "$path" ]]; then
          action="CONFLICT"
          reason="a directory exists where a file is expected"
        else
          current_hash="$(hm_sha256_file "$path" 2>/dev/null || printf '')"
          if [[ -n "$current_hash" && "$current_hash" == "$hash" ]]; then
            # The content is already correct, only the mode can differ.
            current_mode="$(stat -c '%a' -- "$path" 2>/dev/null || printf '')"
            if [[ "$current_mode" == "${octals[$encoded]}" ]]; then
              action="UNCHANGED"
            else
              action="MODE"
            fi
          else
            action="UPDATE"
          fi
        fi
      else
        action="CREATE"
      fi
    fi

    # The parent of a new path has to be a directory.
    if [[ "$action" == "CREATE" ]]; then
      ancestor="${path%/*}"
      if [[ -n "$ancestor" && -e "$ancestor" && ! -d "$ancestor" ]]; then
        action="CONFLICT"
        reason="the parent of the path is not a directory"
      fi
    fi

    actions["$encoded"]="$action"
    reasons["$encoded"]="$reason"

    case "$action" in
      CREATE) create=$((create + 1)) ;;
      UPDATE) update=$((update + 1)) ;;
      MODE) mode_change=$((mode_change + 1)) ;;
      UNCHANGED) unchanged=$((unchanged + 1)) ;;
      CONFLICT) conflict=$((conflict + 1)) ;;
    esac
  done < <(hm_gen_entries "$generation")

  # --- Preview -------------------------------------------------------------
  printf 'Apply preview for generation %s:\n' "$generation"
  printf '\n'

  local encoded
  for encoded in "${order[@]}"; do
    hm_hex_decode path "$encoded"
    case "${actions[$encoded]}" in
      CREATE) printf '  %-10s %s\n' "CREATE" "$(hm_path_display "$path")" ;;
      UPDATE) printf '  %-10s %s\n' "UPDATE" "$(hm_path_display "$path")" ;;
      MODE) printf '  %-10s %s\n' "MODE" "$(hm_path_display "$path")" ;;
      UNCHANGED) printf '  %-10s %s\n' "UNCHANGED" "$(hm_path_display "$path")" ;;
      CONFLICT) printf '  %-10s %s\n' "CONFLICT" "$(hm_path_display "$path")"
        printf '  %-10s %s\n' "" "${reasons[$encoded]}" ;;
    esac
  done

  printf '\n'
  printf '%d created, %d updated, %d mode change(s), %d unchanged, %d conflict(s)\n' \
    "$create" "$update" "$mode_change" "$unchanged" "$conflict"
  printf '\n'

  if [[ $conflict -gt 0 ]]; then
    hm_log_error "The generation cannot be applied, resolve the conflicts first."
    hm_die "$HM_EX_VALIDATION" "$conflict path(s) conflict with the live filesystem."
  fi

  if [[ $create -eq 0 && $update -eq 0 && $mode_change -eq 0 ]]; then
    hm_log_info "The live filesystem is already up to date, nothing was changed."
    return 0
  fi

  if [[ $dry_run -eq 1 ]]; then
    hm_log_info "Dry run, nothing was changed."
    return 0
  fi

  if [[ $assume_yes -eq 0 ]]; then
    if ! hm_confirm "Apply the generation to the live filesystem? [y/N]"; then
      hm_log_info "Cancelled, nothing was changed."
      return 0
    fi
  fi

  # --- Back up the files that are overwritten -------------------------------
  local backup
  backup="$(_apply_backup_dir)"

  local manifest="$backup/manifest.tsv"
  local counter=0 backup_name old_mode

  : > "$manifest"

  for encoded in "${order[@]}"; do
    [[ "${actions[$encoded]}" == "UPDATE" ]] || continue
    hm_hex_decode path "$encoded"

    counter=$((counter + 1))
    backup_name="$(printf '%04d' "$counter")"
    old_mode="$(stat -c '%a' -- "$path" 2>/dev/null || printf '644')"

    if ! cp --preserve=mode,timestamps -- "$path" "$backup/files/$backup_name"; then
      hm_die "$HM_EX_IO" "Cannot back up: $(hm_path_display "$path")"
    fi

    printf 'update\t%s\t%s\t%s\t%s\n' \
      "$encoded" "$backup_name" "$old_mode" "${octals[$encoded]}" >> "$manifest"
  done

  for encoded in "${order[@]}"; do
    case "${actions[$encoded]}" in
      CREATE)
        hm_hex_decode path "$encoded"
        ancestor="$(_apply_missing_ancestor "$path")"
        if [[ -n "$ancestor" ]]; then
          printf 'mkdir\t%s\t-\t-\t-\n' "$(hm_hex_encode "$ancestor")" >> "$manifest"
        fi
        printf 'create\t%s\t-\t-\t%s\n' "$encoded" "${octals[$encoded]}" >> "$manifest"
        ;;
      MODE)
        hm_hex_decode path "$encoded"
        old_mode="$(stat -c '%a' -- "$path" 2>/dev/null || printf '755')"
        printf 'mode\t%s\t-\t%s\t%s\n' "$encoded" "$old_mode" "${octals[$encoded]}" >> "$manifest"
        ;;
    esac
  done

  # --- Write the directories ------------------------------------------------
  # The directories come first, a file needs its parent directory. The
  # recorded mode of a directory is applied at the very end, a directory
  # without write permission would otherwise block its own children.
  for encoded in "${order[@]}"; do
    [[ "${actions[$encoded]}" == "CREATE" ]] || continue
    hm_hex_decode path "$encoded"
    [[ -z "${hashes[$encoded]}" ]] || continue

    if ! mkdir -p -- "$path"; then
      _apply_rollback "$manifest" "$backup"
      hm_die "$HM_EX_IO" "Cannot create the directory: $(hm_path_display "$path")"
    fi
  done

  # --- Write the files ------------------------------------------------------
  local dir tmp

  for encoded in "${order[@]}"; do
    [[ "${actions[$encoded]}" == "CREATE" || "${actions[$encoded]}" == "UPDATE" ]] || continue
    hm_hex_decode path "$encoded"
    hash="${hashes[$encoded]}"

    [[ -n "$hash" ]] || continue

    dir="${path%/*}"
    [[ "$dir" == "$path" ]] && dir="/"
    if ! mkdir -p -- "$dir"; then
      _apply_rollback "$manifest" "$backup"
      hm_die "$HM_EX_IO" "Cannot create the directory: $(hm_path_display "$dir")"
    fi

    tmp="$dir/.hm-apply.$$.tmp"
    rm -f -- "$tmp" 2>/dev/null || true

    if ! cp -- "$(hm_store_path "$hash")" "$tmp"; then
      rm -f -- "$tmp" 2>/dev/null || true
      _apply_rollback "$manifest" "$backup"
      hm_die "$HM_EX_IO" "Cannot stage the content for: $(hm_path_display "$path")"
    fi

    chmod "${octals[$encoded]}" -- "$tmp" 2>/dev/null || true

    if ! mv -f -- "$tmp" "$path"; then
      rm -f -- "$tmp" 2>/dev/null || true
      _apply_rollback "$manifest" "$backup"
      hm_die "$HM_EX_IO" "Cannot write: $(hm_path_display "$path")"
    fi
  done

  # --- Apply the recorded modes --------------------------------------------
  # The mode of a directory is applied at the very end, a directory without
  # write permission would otherwise block its own children. A file whose
  # content is already correct only gets its mode corrected.
  for encoded in "${order[@]}"; do
    [[ "${actions[$encoded]}" == "CREATE" || "${actions[$encoded]}" == "MODE" ]] || continue
    hm_hex_decode path "$encoded"
    hash="${hashes[$encoded]}"

    if [[ -z "$hash" || "${actions[$encoded]}" == "MODE" ]]; then
      chmod "${octals[$encoded]}" -- "$path" 2>/dev/null || true
    fi
  done

  # --- Verify ---------------------------------------------------------------
  local target_hash

  for encoded in "${order[@]}"; do
    [[ "${actions[$encoded]}" == "CREATE" || "${actions[$encoded]}" == "UPDATE" ]] || continue
    hm_hex_decode path "$encoded"
    hash="${hashes[$encoded]}"
    [[ -n "$hash" ]] || continue

    target_hash="$(hm_sha256_file "$path" 2>/dev/null || printf '')"
    if [[ "$target_hash" != "$hash" ]]; then
      hm_log_error "The verification of $(hm_path_display "$path") failed."
      _apply_rollback "$manifest" "$backup"
      hm_die "$HM_EX_IO" "The verification failed, the operation was rolled back."
    fi
  done

  hm_log_success "Generation $generation was applied."
  printf '%s\n' "Created:   $create"
  printf '%s\n' "Updated:   $update"
  printf '%s\n' "Modes:     $mode_change"
  printf '%s\n' "Unchanged: $unchanged"
  printf '%s\n' "Backup:    $(hm_path_display "$backup")"

  return 0
}
