#!/usr/bin/env bash
#
# lib/validation.sh - runtime paths and project validation.
#
# The file only defines functions. Sourcing it has no side effects.
#

# Schema version implemented by this code base. The authoritative schema
# file sets the same value with "PRAGMA user_version", the test suite
# verifies that both stay in sync.
HM_SCHEMA_VERSION=2

# hm_runtime_init - derive every runtime path from the project directory.
# It only computes values, it never touches the filesystem.
#
# The paths are consumed by the other modules, shellcheck only sees this
# file and therefore reports the ones it cannot find here.
# shellcheck disable=SC2034
hm_runtime_init() {
  HM_DIR="${HM_DIR%/}"
  [[ -n "$HM_DIR" ]] || HM_DIR="/"

  HM_DB_FILE="$HM_DIR/db.sqlite"
  HM_STORE_ROOT="$HM_DIR/store/objects"
  HM_TMP_DIR="$HM_DIR/tmp"
  HM_LOG_DIR="$HM_DIR/logs"
  HM_BACKUP_DIR="$HM_DIR/backup"
  HM_CURRENT_DIR="$HM_DIR/current"
  HM_TESTING_DIR="$HM_DIR/testing"
  HM_LOCK_FILE="$HM_DIR/hm.lock"
  HM_CONFIG_FILE="$HM_DIR/config"
}

# hm_schema_file - print the location of the authoritative schema file.
# Resolution order:
#   1. the HM_SCHEMA_FILE environment variable
#   2. <code directory>/db/schema.sql   (normal installation)
#   3. <runtime directory>/db/schema.sql (self contained installation)
hm_schema_file() {
  local candidate

  if [[ -n "${HM_SCHEMA_FILE:-}" ]]; then
    printf '%s\n' "$HM_SCHEMA_FILE"
    return 0
  fi

  candidate="$HM_CODE_DIR/db/schema.sql"
  if [[ -f "$candidate" ]]; then
    printf '%s\n' "$candidate"
    return 0
  fi

  candidate="$HM_DIR/db/schema.sql"
  if [[ -f "$candidate" ]]; then
    printf '%s\n' "$candidate"
    return 0
  fi

  return 1
}

# hm_runtime_directories - the directories that a project must provide.
hm_runtime_directories() {
  printf '%s\n' \
    "$HM_DIR" \
    "$HM_STORE_ROOT" \
    "$HM_TMP_DIR" \
    "$HM_LOG_DIR" \
    "$HM_BACKUP_DIR" \
    "$HM_CURRENT_DIR" \
    "$HM_TESTING_DIR"
}

# hm_validate_schema_file - make sure the authoritative schema is available.
hm_validate_schema_file() {
  local schema

  if ! schema="$(hm_schema_file)"; then
    hm_die "$HM_EX_VALIDATION" "The database schema file was not found. Expected it in $HM_CODE_DIR/db/schema.sql"
  fi
  if [[ ! -r "$schema" ]]; then
    hm_die "$HM_EX_VALIDATION" "The database schema file is not readable: $schema"
  fi

  printf '%s\n' "$schema"
}

# hm_validate_runtime - make sure the project directory structure exists.
hm_validate_runtime() {
  local dir missing=0

  while IFS= read -r dir; do
    if [[ ! -d "$dir" ]]; then
      hm_log_warn "Missing project directory: $(hm_path_display "$dir")"
      missing=1
    fi
  done < <(hm_runtime_directories)

  [[ $missing -eq 0 ]] || hm_die "$HM_EX_VALIDATION" "The project is not initialized. Run 'hm init' first."
  return 0
}

# hm_validate_db - integrity, foreign keys and schema version of the
# project database.
hm_validate_db() {
  local db integrity fk version expected

  db="$(hm_db_file)"

  if [[ ! -f "$db" ]]; then
    hm_die "$HM_EX_VALIDATION" "Database not found: $(hm_path_display "$db"). Run 'hm init' first."
  fi

  integrity="$(sqlite3 "$db" 'PRAGMA integrity_check;' 2>/dev/null || printf 'unavailable')"
  if [[ "$integrity" != "ok" ]]; then
    hm_die "$HM_EX_DB" "Database integrity check failed: $integrity"
  fi

  fk="$(sqlite3 "$db" 'PRAGMA foreign_key_check;' 2>/dev/null || printf 'unavailable')"
  if [[ -n "$fk" ]]; then
    hm_die "$HM_EX_DB" "Database foreign key check failed."
  fi

  version="$(hm_db_schema_version 2>/dev/null || printf 'unknown')"
  expected="$(hm_schema_version_expected)"

  if [[ "$version" != "$expected" ]]; then
    if [[ "$version" =~ ^[0-9]+$ ]] && [[ "$version" -lt "$expected" ]]; then
      hm_die "$HM_EX_DB" "The database schema is version $version but this HM-Lite build requires version $expected. Run 'hm init' to apply the pending migrations."
    fi
    hm_die "$HM_EX_DB" "The database schema is version $version but this HM-Lite build requires version $expected. The database was created by a newer HM-Lite version."
  fi

  return 0
}

# hm_schema_version_expected - the schema version this build implements.
hm_schema_version_expected() {
  printf '%s\n' "$HM_SCHEMA_VERSION"
}

# hm_validate_store - make sure the content store is usable.
hm_validate_store() {
  if [[ ! -d "$HM_STORE_ROOT" ]]; then
    hm_die "$HM_EX_VALIDATION" "Content store not found: $(hm_path_display "$HM_STORE_ROOT"). Run 'hm init' first."
  fi
  return 0
}

# hm_require_initialized - the precondition of every command that works on
# an existing project.
hm_require_initialized() {
  hm_validate_runtime
  hm_validate_db
  hm_validate_store
  hm_validate_schema_file > /dev/null
  return 0
}
