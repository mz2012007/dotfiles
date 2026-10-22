#!/usr/bin/env bash
#
# core/restore.sh - the restore command.
#
# Restores a backup that was created with "hm backup". The archive is
# validated before anything is changed:
#
#   * every member name must be relative and must not escape the archive,
#   * the extracted tree must not contain a symbolic link,
#   * every file must match the checksum of the manifest,
#   * the schema version of the restored database must be supported.
#
# The current state is moved aside first, a failure restores it.
#

# --- Helpers ---------------------------------------------------------------

# _restore_usage
_restore_usage() {
  cat <<'EOF'
Usage: hm restore <backup> [options]

Restore a backup that was created with "hm backup".

Options:
  --yes, -y      Do not ask for a confirmation
  -h, --help     Show this help
EOF
}

# _restore_cleanup_stage
_restore_cleanup_stage() {
  local stage="${_RESTORE_STAGE:-}"

  trap - EXIT
  _RESTORE_STAGE=""

  [[ -n "$stage" ]] || return 0
  hm_rm_rf_under "${HM_TMP_DIR:-/nonexistent}" "$stage" 2>/dev/null || true
  return 0
}

# _restore_validate_members ARCHIVE
# Refuse an archive that holds an unsafe member name.
_restore_validate_members() {
  local archive="$1" member

  while IFS= read -r member; do
    [[ -n "$member" ]] || continue
    case "$member" in
      /* | .. | ../* | */../* | */..)
        hm_die "$HM_EX_VALIDATION" "The backup holds an unsafe member: $member"
        ;;
    esac
  done < <(tar -tzf "$archive" 2>/dev/null)

  return 0
}

# --- The command -----------------------------------------------------------

# restore ARCHIVE - restore a backup.
restore() {
  local archive=""
  local assume_yes=0
  local argument

  while [[ $# -gt 0 ]]; do
    argument="$1"
    case "$argument" in
      --yes | -y)
        assume_yes=1
        shift
        ;;
      -h | --help)
        _restore_usage
        return 0
        ;;
      -*)
        hm_die "$HM_EX_USAGE" "Unknown option for 'hm restore': $argument"
        ;;
      *)
        if [[ -n "$archive" ]]; then
          hm_die "$HM_EX_USAGE" "Usage: hm restore <backup>"
        fi
        archive="$argument"
        shift
        ;;
    esac
  done

  if [[ -z "$archive" ]]; then
    hm_die "$HM_EX_USAGE" "Usage: hm restore <backup>"
  fi

  hm_require_cmd tar sha256sum sqlite3
  hm_require_initialized
  hm_lock_acquire exclusive

  if [[ ! -f "$archive" ]]; then
    hm_die "$HM_EX_VALIDATION" "The backup file does not exist: $(hm_path_display "$archive")"
  fi

  # --- Validate the archive -------------------------------------------------
  if ! tar -tzf "$archive" > /dev/null 2>&1; then
    hm_die "$HM_EX_VALIDATION" "The backup file is not a readable archive: $(hm_path_display "$archive")"
  fi

  _restore_validate_members "$archive"

  local stage
  stage="$(hm_mktemp_dir "restore.XXXXXXXX")" || hm_die "$HM_EX_IO" "Cannot create the staging directory."
  _RESTORE_STAGE="$stage"
  trap '_restore_cleanup_stage' EXIT

  if ! tar -xzf "$archive" -C "$stage" --no-same-owner --no-same-permissions; then
    hm_die "$HM_EX_VALIDATION" "The backup archive cannot be extracted."
  fi

  if [[ ! -f "$stage/db.sqlite" || ! -f "$stage/manifest.tsv" ]]; then
    hm_die "$HM_EX_VALIDATION" "The backup archive does not hold a database and a manifest."
  fi

  if [[ -n "$(find "$stage" -type l -print -quit 2>/dev/null)" ]]; then
    hm_die "$HM_EX_VALIDATION" "The backup archive holds a symbolic link."
  fi

  if ! (cd -- "$stage" && sha256sum -c --quiet -- manifest.tsv > /dev/null 2>&1); then
    hm_die "$HM_EX_VALIDATION" "The backup archive is damaged, the checksum verification failed."
  fi

  local version expected
  version="$(sqlite3 "$stage/db.sqlite" 'PRAGMA user_version;' 2>/dev/null || printf '')"
  expected="$(hm_schema_version_expected)"

  if [[ "$version" != "$expected" ]]; then
    hm_die "$HM_EX_VALIDATION" "The backup uses the schema version $version but this build requires $expected."
  fi

  # --- Preview --------------------------------------------------------------
  local generations paths objects
  generations="$(sqlite3 "$stage/db.sqlite" 'SELECT COUNT(*) FROM generations;' 2>/dev/null || printf '?')"
  paths="$(sqlite3 "$stage/db.sqlite" 'SELECT COUNT(*) FROM paths;' 2>/dev/null || printf '?')"
  objects="$(sqlite3 "$stage/db.sqlite" 'SELECT COUNT(*) FROM files;' 2>/dev/null || printf '?')"

  printf '%sRestore preview:%s\n' "$HM_C_OUT_BOLD" "$HM_C_OUT_RESET"
  printf '\n'
  printf '  Backup:       %s%s%s\n' "$HM_C_OUT_CYAN" "$(hm_path_display "$archive")" "$HM_C_OUT_RESET"
  printf '  Generations:  %s\n' "$generations"
  printf '  Paths:        %s\n' "$paths"
  printf '  Objects:      %s\n' "$objects"
  printf '\n'
  printf '%s\n' "The current database and the current content store are replaced."
  printf '%s\n' "The current/ and testing/ workspaces are cleared."
  printf '\n'

  if [[ $assume_yes -eq 0 ]]; then
    if ! hm_confirm "Restore the backup? [y/N]"; then
      hm_log_info "Cancelled, nothing was changed."
      return "$HM_EX_DECLINED"
    fi
  fi

  # --- Activate the restored state -----------------------------------------
  local previous="$HM_TMP_DIR/restore.previous.$$"
  rm -rf -- "$previous"
  mkdir -p -- "$previous" || hm_die "$HM_EX_IO" "Cannot create the restore directory."

  if ! mv -- "$HM_DB_FILE" "$previous/db.sqlite"; then
    hm_die "$HM_EX_IO" "Cannot move the current database aside."
  fi
  if ! mv -- "$HM_STORE_ROOT" "$previous/store"; then
    mv -- "$previous/db.sqlite" "$HM_DB_FILE" 2>/dev/null || true
    hm_die "$HM_EX_IO" "Cannot move the current content store aside."
  fi

  if ! mv -- "$stage/db.sqlite" "$HM_DB_FILE"; then
    mv -- "$previous/store" "$HM_STORE_ROOT" 2>/dev/null || true
    mv -- "$previous/db.sqlite" "$HM_DB_FILE" 2>/dev/null || true
    hm_die "$HM_EX_IO" "Cannot install the restored database."
  fi

  if ! mv -- "$stage/store" "$HM_STORE_ROOT"; then
    rm -f -- "$HM_DB_FILE" 2>/dev/null || true
    mv -- "$previous/store" "$HM_STORE_ROOT" 2>/dev/null || true
    mv -- "$previous/db.sqlite" "$HM_DB_FILE" 2>/dev/null || true
    hm_die "$HM_EX_IO" "Cannot install the restored content store."
  fi

  _RESTORE_STAGE=""
  trap - EXIT
  hm_rm_rf_under "$HM_TMP_DIR" "$stage" 2>/dev/null || true
  hm_rm_rf_under "$HM_TMP_DIR" "$previous" 2>/dev/null || true

  # The materialized workspaces belong to the state that was replaced.
  hm_rm_rf_under "$HM_DIR" "$HM_CURRENT_DIR" 2>/dev/null || true
  hm_rm_rf_under "$HM_DIR" "$HM_TESTING_DIR" 2>/dev/null || true
  mkdir -p -- "$HM_CURRENT_DIR" "$HM_TESTING_DIR" 2>/dev/null || true
  chmod 700 -- "$HM_CURRENT_DIR" "$HM_TESTING_DIR" 2>/dev/null || true

  hm_log_success "The backup was restored."

  return 0
}
