#!/usr/bin/env bash
#
# core/init.sh - the init command.
#
# Initializes an HM-Lite project directory. The command is idempotent, it
# never destroys an existing valid project.
#
# The module only defines the init function. Sourcing it does not run the
# command.
#

# hm_init_create_dirs - create the project directory structure.
hm_init_create_dirs() {
  local dir
  local -a dirs=()

  while IFS= read -r dir; do
    dirs+=("$dir")
  done < <(hm_runtime_directories)

  for dir in "${dirs[@]}"; do
    if [[ -e "$dir" && ! -d "$dir" ]]; then
      hm_die "$HM_EX_VALIDATION" "Cannot create the project directory, the path exists and is not a directory: $(hm_path_display "$dir")"
    fi
  done

  for dir in "${dirs[@]}"; do
    if ! mkdir -p -- "$dir"; then
      hm_die "$HM_EX_IO" "Cannot create the project directory: $(hm_path_display "$dir")"
    fi
  done

  # Private state, the store and the database may contain private files.
  chmod 700 -- "$HM_DIR" 2>/dev/null || true
  chmod 700 -- "$HM_STORE_ROOT" 2>/dev/null || true
  chmod 700 -- "$HM_TMP_DIR" 2>/dev/null || true
  chmod 700 -- "$HM_LOG_DIR" 2>/dev/null || true
  chmod 700 -- "$HM_BACKUP_DIR" 2>/dev/null || true
  chmod 700 -- "$HM_CURRENT_DIR" 2>/dev/null || true
  chmod 700 -- "$HM_TESTING_DIR" 2>/dev/null || true

  return 0
}

# hm_init_write_config - create the configuration file when it is missing.
# An existing configuration file is never modified.
hm_init_write_config() {
  local template="$HM_CODE_DIR/config"

  if [[ -f "$HM_CONFIG_FILE" ]]; then
    hm_log_info "Keeping the existing configuration file: $(hm_path_display "$HM_CONFIG_FILE")"
    return 0
  fi

  if [[ ! -f "$template" ]]; then
    hm_log_warn "No configuration template found at $(hm_path_display "$template"), skipping."
    return 0
  fi

  if ! cp -- "$template" "$HM_CONFIG_FILE"; then
    hm_die "$HM_EX_IO" "Cannot write the configuration file: $(hm_path_display "$HM_CONFIG_FILE")"
  fi
  chmod 600 -- "$HM_CONFIG_FILE" 2>/dev/null || true

  hm_log_info "Created the configuration file."
  return 0
}

# hm_init_database - create or validate the project database.
hm_init_database() {
  local schema db version expected

  schema="$(hm_validate_schema_file)"
  db="$(hm_db_file)"
  expected="$(hm_schema_version_expected)"

  if [[ ! -f "$db" ]]; then
    hm_log_info "Creating the database: $(hm_path_display "$db")"
    if ! hm_db_apply_schema "$schema"; then
      hm_die "$HM_EX_DB" "Cannot initialize the database."
    fi
    chmod 600 -- "$db" 2>/dev/null || true
    return 0
  fi

  hm_log_info "The database already exists, validating it instead of replacing it."
  version="$(hm_db_schema_version 2>/dev/null || printf 'unknown')"

  if [[ "$version" == "$expected" ]]; then
    hm_log_info "Database schema version $version is up to date."
    return 0
  fi

  if [[ "$version" =~ ^[0-9]+$ ]] && [[ "$version" -lt "$expected" ]]; then
    hm_log_info "Applying the pending schema migrations."
    hm_apply_migrations "$version" "$expected" || hm_die "$HM_EX_DB" "The schema migration failed, the project was left unchanged."
    return 0
  fi

  if [[ ! "$version" =~ ^[0-9]+$ ]]; then
    hm_die "$HM_EX_DB" "The database is not a readable SQLite database: $(hm_path_display "$db")"
  fi

  hm_die "$HM_EX_DB" "The database schema is version $version but this build requires version $expected. The database was created by a newer HM-Lite version."
}

# init - initialize the HM-Lite project.
init() {
  local algorithm argument

  for argument in "$@"; do
    case "$argument" in
      -h | --help)
        printf 'Usage: hm init\n'
        return 0
        ;;
      *)
        hm_die "$HM_EX_USAGE" "Usage: hm init"
        ;;
    esac
  done

  algorithm="$(hm_config_get HM_HASH_ALGORITHM sha256)"
  if [[ "$algorithm" != "sha256" ]]; then
    hm_die "$HM_EX_VALIDATION" "Unsupported hashing algorithm: $algorithm (only sha256 is implemented)"
  fi

  hm_log_info "Initializing HM-Lite in: $(hm_path_display "$HM_DIR")"

  hm_init_create_dirs
  hm_init_write_config
  hm_init_database

  # Internal state records.
  hm_db_exec "INSERT INTO schema_meta (key, value) VALUES ('created_at', $(hm_sql_quote "$(hm_now_utc)"))
              ON CONFLICT(key) DO NOTHING;"
  hm_db_exec "INSERT INTO schema_meta (key, value) VALUES ('hm_version', $(hm_sql_quote "$HM_VERSION"))
              ON CONFLICT(key) DO UPDATE SET value = excluded.value;"

  # Validate the result before reporting success.
  hm_validate_runtime
  hm_validate_db
  hm_validate_store

  hm_log_success "HM-Lite is initialized."
  printf '%s\n' "Project directory: $HM_DIR"
  printf '%s\n' "Database:          $(hm_path_display "$(hm_db_file)")"
  printf '%s\n' "Content store:     $(hm_path_display "$HM_STORE_ROOT")"
  printf '%s\n' ""
  printf '%s\n' "Next step: hm add <file|directory...>"
  return 0
}
