#!/usr/bin/env bash
#
# core/backup.sh - the backup command.
#
# Creates a consistent backup of the project state. The backup is a single
# compressed archive that holds
#
#   db.sqlite     a consistent copy of the database, taken with the sqlite
#                 backup command while the project lock is held
#   store/        the content addressable store
#   manifest.tsv  the SHA-256 checksum of every archived file
#   meta.txt      the version and the creation time of the backup
#
# The manifest uses the format of sha256sum, therefore the integrity of the
# archive can be verified with "sha256sum -c manifest.tsv".
#

# --- Helpers ---------------------------------------------------------------

# _backup_usage
_backup_usage() {
  cat <<'EOF'
Usage: hm backup [options]

Create a consistent backup of the project state.

The backup never changes the project state, therefore it does not ask for a
confirmation and it can be run from a cron job.

Options:
  -h, --help     Show this help
EOF
}

# _backup_cleanup_stage
_backup_cleanup_stage() {
  local stage="${_BACKUP_STAGE:-}"

  trap - EXIT
  _BACKUP_STAGE=""

  [[ -n "$stage" ]] || return 0
  hm_rm_rf_under "${HM_TMP_DIR:-/nonexistent}" "$stage" 2>/dev/null || true
  return 0
}

# --- The command -----------------------------------------------------------

# backup - create a consistent backup of the project state.
backup() {
  local argument

  while [[ $# -gt 0 ]]; do
    argument="$1"
    case "$argument" in
      -h | --help)
        _backup_usage
        return 0
        ;;
      *)
        hm_die "$HM_EX_USAGE" "Unknown argument for 'hm backup': $argument"
        ;;
    esac
  done

  hm_require_cmd sqlite3 tar sha256sum
  hm_require_initialized
  hm_lock_acquire exclusive

  local stamp archive stage
  stamp="$(hm_utc_stamp)"
  archive="$HM_BACKUP_DIR/hm-backup-$stamp.tar.gz"

  if [[ -e "$archive" ]]; then
    hm_die "$HM_EX_IO" "The backup file exists already: $(hm_path_display "$archive")"
  fi

  # --- Stage the backup ----------------------------------------------------
  stage="$(hm_mktemp_dir "backup.XXXXXXXX")" || hm_die "$HM_EX_IO" "Cannot create the staging directory."
  _BACKUP_STAGE="$stage"
  trap '_backup_cleanup_stage' EXIT

  mkdir -p -- "$stage/store" || hm_die "$HM_EX_IO" "Cannot create the store directory."

  # A consistent copy of the database. The project lock is held, therefore
  # no other process writes to the database while it is copied.
  local db_target="${stage//\'/\'\'}"
  if ! sqlite3 "$(hm_db_file)" ".backup '$db_target/db.sqlite'"; then
    hm_die "$HM_EX_DB" "Cannot copy the database."
  fi

  if ! cp -a -- "$HM_STORE_ROOT/." "$stage/store/"; then
    hm_die "$HM_EX_IO" "Cannot copy the content store."
  fi

  {
    printf 'hm_version=%s\n' "$HM_VERSION"
    printf 'created_at=%s\n' "$(hm_now_utc)"
    printf 'schema_version=%s\n' "$(hm_schema_version_expected)"
    printf 'generations=%s\n' "$(hm_db_scalar 'SELECT COUNT(*) FROM generations;')"
    printf 'paths=%s\n' "$(hm_db_scalar 'SELECT COUNT(*) FROM paths;')"
    printf 'objects=%s\n' "$(hm_db_scalar 'SELECT COUNT(*) FROM files;')"
  } > "$stage/meta.txt"

  # The manifest. The name of a store object is the hash of its content,
  # therefore the file name can be used as the checksum.
  (
    cd -- "$stage" || exit 1
    while IFS= read -r -d '' file; do
      local relative="${file#./}" checksum
      case "$relative" in
        store/*) checksum="${relative##*/}" ;;
        *) checksum="$(sha256sum -- "$file" | cut -d' ' -f1)" ;;
      esac
      printf '%s  %s\n' "$checksum" "$relative"
    done < <(find . -type f ! -name manifest.tsv -print0 | sort -z)
  ) > "$stage/manifest.tsv"

  # --- Write the archive ----------------------------------------------------
  local temporary="$archive.tmp"
  if ! tar -czf "$temporary" -C "$stage" db.sqlite store manifest.tsv meta.txt; then
    rm -f -- "$temporary" 2>/dev/null || true
    hm_die "$HM_EX_IO" "Cannot write the backup archive."
  fi
  chmod 600 -- "$temporary" 2>/dev/null || true

  # The archive is only published when it can be read again.
  if ! tar -tzf "$temporary" > /dev/null 2>&1; then
    rm -f -- "$temporary" 2>/dev/null || true
    hm_die "$HM_EX_IO" "The written backup archive cannot be read, it was discarded."
  fi

  mv -f -- "$temporary" "$archive" || {
    rm -f -- "$temporary" 2>/dev/null || true
    hm_die "$HM_EX_IO" "Cannot publish the backup archive."
  }

  _BACKUP_STAGE=""
  trap - EXIT
  hm_rm_rf_under "$HM_TMP_DIR" "$stage" 2>/dev/null || true

  local size
  size="$(stat -c '%s' -- "$archive" 2>/dev/null || printf '0')"

  hm_log_success "The backup was created."
  printf 'Backup:   %s%s%s\n' "$HM_C_OUT_GREEN" "$(hm_path_display "$archive")" "$HM_C_OUT_RESET"
  printf 'Size:     %s bytes\n' "$size"
  printf 'Restore:  %shm restore %s%s\n' "$HM_C_OUT_CYAN" "$(hm_path_display "$archive")" "$HM_C_OUT_RESET"

  return 0
}
