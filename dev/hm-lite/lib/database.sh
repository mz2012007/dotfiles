#!/usr/bin/env bash
#
# lib/database.sh - SQLite access layer.
#
# HM-Lite uses the sqlite3 command line client. Two mechanisms guarantee
# that user controlled data never breaks out of a statement:
#
#   * Values are embedded with hm_sql_quote, which doubles every single
#     quote. SQLite string literals have no backslash escapes, therefore
#     doubling the quote is the complete and correct escaping rule.
#   * Values are read back with hex(), so a value can never break the
#     field separator of the result format. The hex form is decoded again
#     by hm_hex_decode.
#
# The file only defines functions. Sourcing it has no side effects.
#

# Field separator used in query results. Text columns are read back hex
# encoded, therefore this byte cannot appear inside a decoded value.
HM_FIELD_SEP=$'\x1f'

# hm_db_file - absolute path of the project database.
hm_db_file() {
  printf '%s\n' "${HM_DB_FILE:-$HM_DIR/db.sqlite}"
}

# --- Value quoting --------------------------------------------------------

# hm_sql_quote TEXT
# Return TEXT as a quoted SQLite string literal.
hm_sql_quote() {
  local value="$1"
  value="${value//\'/\'\'}"
  printf "'%s'" "$value"
}

# hm_sql_int VALUE
# Return VALUE as an SQL integer literal. The value must be a decimal
# integer, anything else is a hard error.
hm_sql_int() {
  local value="$1"
  if [[ ! "$value" =~ ^-?[0-9]+$ ]]; then
    hm_die "$HM_EX_VALIDATION" "Expected an integer value, got: $value"
  fi
  printf '%s' "$value"
}

# --- Hex encoding ---------------------------------------------------------

# hm_hex_decode VARIABLE HEX
# Decode a hexadecimal string into VARIABLE. The decode is byte exact, it
# preserves newlines and every other byte, and it does not use a command
# substitution, therefore no trailing newline is ever lost.
hm_hex_decode() {
  local -n hm__hex_out="$1"
  local hex="$2"
  local i byte

  hm__hex_out=''
  [[ -n "$hex" ]] || return 0

  for ((i = 0; i < ${#hex}; i += 2)); do
    printf -v byte '%b' "\\x${hex:i:2}"
    hm__hex_out+="$byte"
  done
  return 0
}

# hm_hex_encode TEXT
# Print the hexadecimal representation of TEXT. The encoding is byte exact
# and locale independent.
hm_hex_encode() {
  local value="$1"

  [[ -n "$value" ]] || return 0

  printf '%s' "$value" | od -An -v -tx1 | tr -d ' \n'
  return 0
}

# --- Running statements ---------------------------------------------------

# _hm_sqlite_header - the connection settings of every statement.
#
# The settings are sent as part of the script instead of using the sqlite3
# "-cmd" option, because the combination of "-bail" and "-cmd" makes the
# sqlite3 command line client skip the actual statement.
#
# "PRAGMA busy_timeout = 5000" is not used because the assignment form
# returns the new value as an additional result row. The dot command
# ".timeout" sets the same value without producing any output.
_hm_sqlite_header() {
  printf 'PRAGMA foreign_keys = ON;\n'
  printf '.timeout %s\n' "${HM_DB_TIMEOUT:-5000}"
}

# _hm_sqlite_script - execute a SQL script read from standard input.
_hm_sqlite_script() {
  {
    _hm_sqlite_header
    cat
  } | sqlite3 -bail "$(hm_db_file)"
}

# hm_db_exec SQL
# Execute a statement that produces no result rows.
hm_db_exec() {
  {
    _hm_sqlite_header
    printf '%s\n' "$1"
  } | sqlite3 -bail "$(hm_db_file)" > /dev/null
}

# hm_db_query SQL
# Execute a statement and print the result rows. Columns are separated by
# HM_FIELD_SEP, rows are separated by newlines.
hm_db_query() {
  {
    _hm_sqlite_header
    printf '%s\n' "$1"
  } | sqlite3 -bail "$(hm_db_file)" -separator "$HM_FIELD_SEP"
}

# hm_db_scalar SQL
# Execute a statement and print the first column of the first row.
hm_db_scalar() {
  {
    _hm_sqlite_header
    printf '%s\n' "$1"
  } | sqlite3 -bail "$(hm_db_file)" -noheader -list
}

# hm_db_rows SQL VARIABLE
# Execute a statement and store the result rows in VARIABLE, one row per
# line. The rows use the same format as hm_db_query.
#
# The function fails with HM_EX_DB when the statement fails. This is the
# only safe way to read a result set: a shell process substitution hides
# the exit status of the command it runs, therefore an empty result and a
# failed query would be indistinguishable.
hm_db_rows() {
  local sql="$1"
  # The nameref writes into the variable of the caller, shellcheck cannot
  # see through it.
  # shellcheck disable=SC2034
  local -n hm__rows_ref="$2"

  # shellcheck disable=SC2034
  hm__rows_ref="$(hm_db_query "$sql")" || return "$HM_EX_DB"
  return 0
}

# hm_db_tx
# Read SQL statements from standard input and execute them inside a single
# transaction. The transaction is committed only when every statement
# succeeded, otherwise it is rolled back and the function fails with
# HM_EX_DB.
hm_db_tx() {
  local sql_file rc

  sql_file="$(hm_mktemp_file)" || return "$HM_EX_IO"
  {
    printf 'BEGIN IMMEDIATE;\n'
    cat
    printf '\nCOMMIT;\n'
  } > "$sql_file"

  rc=0
  _hm_sqlite_script < "$sql_file" > /dev/null || rc=$?

  if [[ $rc -ne 0 ]]; then
    sqlite3 "$(hm_db_file)" 'ROLLBACK;' > /dev/null 2>&1 || true
    rm -f -- "$sql_file"
    return "$HM_EX_DB"
  fi

  rm -f -- "$sql_file"
  return 0
}

# --- Schema management ----------------------------------------------------

# hm_db_schema_version - print the schema version of the project database.
hm_db_schema_version() {
  hm_db_scalar 'PRAGMA user_version;'
}

# hm_db_apply_schema FILE
# Apply an authoritative schema file to the project database. The file is
# the single source of truth for the schema, no schema statement is ever
# duplicated inside the shell code.
hm_db_apply_schema() {
  local file="$1"

  [[ -f "$file" ]] || {
    hm_die "$HM_EX_VALIDATION" "Schema file not found: $file"
  }

  _hm_sqlite_script < "$file" > /dev/null
}

# hm_db_migration_files - print the migration files in order.
hm_db_migration_files() {
  local dir="${HM_MIGRATIONS_DIR:-$HM_CODE_DIR/db/migrations}"
  local file

  [[ -d "$dir" ]] || return 0

  while IFS= read -r file; do
    printf '%s\n' "$file"
  done < <(find "$dir" -maxdepth 1 -type f -name '*.sql' -print | sort)
}

# hm_apply_migrations CURRENT_VERSION TARGET_VERSION
# Apply the schema migrations that are needed to move the database from
# CURRENT_VERSION to TARGET_VERSION. Every migration is applied inside its
# own transaction, a failing migration leaves the database unchanged.
hm_apply_migrations() {
  local current="$1" target="$2"
  local file version sql_file

  while IFS= read -r file; do
    [[ -n "$file" ]] || continue

    version="$(grep -oE 'PRAGMA[[:space:]]+user_version[[:space:]]*=[[:space:]]*[0-9]+' -- "$file" |
      grep -oE '[0-9]+$' || true)"

    if [[ -z "$version" ]]; then
      hm_log_warn "Migration without a user_version statement, skipping: $(hm_path_display "$file")"
      continue
    fi

    if [[ "$version" -le "$current" ]]; then
      continue
    fi

    if [[ "$version" -gt "$target" ]]; then
      hm_die "$HM_EX_DB" "The migration $(hm_path_display "$file") targets schema version $version which is newer than the expected version $target."
    fi

    hm_log_info "Applying migration: $(hm_path_display "$file")"

    sql_file="$(hm_mktemp_file)" || return "$HM_EX_IO"
    {
      printf 'BEGIN IMMEDIATE;\n'
      cat -- "$file"
      printf '\nCOMMIT;\n'
    } > "$sql_file"

    if ! _hm_sqlite_script < "$sql_file" > /dev/null; then
      sqlite3 "$(hm_db_file)" 'ROLLBACK;' > /dev/null 2>&1 || true
      rm -f -- "$sql_file"
      hm_die "$HM_EX_DB" "The migration failed: $(hm_path_display "$file")"
    fi
    rm -f -- "$sql_file"

    current="$version"
  done < <(hm_db_migration_files)

  return 0
}
