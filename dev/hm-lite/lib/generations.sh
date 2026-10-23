#!/usr/bin/env bash
#
# lib/generations.sh - generation helpers and materialization.
#
# A generation is an immutable historical state. The functions here read
# generations and materialize them into a working directory.
#
# Materialization mirrors the absolute path of every entry below the target
# directory: the entry /home/user/.bashrc is written to
# <target>/home/user/.bashrc. The mapping is unambiguous and it allows the
# same tree to hold entries that live in different roots.
#
# The file only defines functions. Sourcing it has no side effects.
#

# hm_gen_selected [PROFILE] - print the id of the selected generation of
# the profile, if any. Without a profile the global selection is read.
# An empty result means that no generation was selected, a database error
# is reported and never hidden behind an empty result.
hm_gen_selected() {
  local profile="${1:-}" key value

  key="$(hm_profile_state_key "$profile")"
  value="$(hm_db_scalar "SELECT value FROM state WHERE key = $(hm_sql_quote "$key");")" ||
    hm_die "$HM_EX_DB" "Cannot read the selected generation from the database."

  printf '%s\n' "$value"
}

# hm_gen_is_selected GENERATION_ID [PROFILE]
# Return 0 when the generation is the selection of the profile. Without a
# profile the global selection is compared.
hm_gen_is_selected() {
  local id selected

  id="$(hm_sql_int "$1")"
  selected="$(hm_gen_selected "${2:-}")"

  [[ -n "$selected" && "$id" == "$selected" ]]
}

# hm_gen_latest [PROFILE] - print the id of the newest generation.
# The order is created_at DESC, id DESC, the identifier alone is not an
# order because it does not reflect the creation time. With a profile the
# newest generation of that profile is returned.
hm_gen_latest() {
  local profile="${1:-}" value

  if [[ -n "$profile" ]]; then
    value="$(hm_db_scalar "
      SELECT g.id
        FROM generations g
        JOIN profiles pr ON pr.id = g.profile_id
       WHERE pr.name = $(hm_sql_quote "$profile")
       ORDER BY g.created_at DESC, g.id DESC
       LIMIT 1;")" ||
      hm_die "$HM_EX_DB" "Cannot read the generations from the database."
  else
    value="$(hm_db_scalar "SELECT id FROM generations ORDER BY created_at DESC, id DESC LIMIT 1;")" ||
      hm_die "$HM_EX_DB" "Cannot read the generations from the database."
  fi

  printf '%s\n' "$value"
}

# hm_gen_number GENERATION_ID
# Print the local number of the generation. An unknown id prints nothing
# and returns 1, a database error aborts the command.
hm_gen_number() {
  local id number

  id="$(hm_sql_int "$1")"
  number="$(hm_db_scalar "SELECT number FROM generations WHERE id = $id;")" ||
    hm_die "$HM_EX_DB" "Cannot read the number of the generation $id from the database."

  [[ -n "$number" ]] || return 1
  printf '%s\n' "$number"
}

# hm_gen_label GENERATION_ID
# Print "profile:number" for the generation. The label is unambiguous when a
# command works across profiles, for example "hm discard".
hm_gen_label() {
  local id label

  id="$(hm_sql_int "$1")"
  label="$(hm_db_scalar "
    SELECT pr.name || ':' || g.number
      FROM generations g
      JOIN profiles pr ON pr.id = g.profile_id
     WHERE g.id = $id;")" ||
    hm_die "$HM_EX_DB" "Cannot read the generation $id from the database."

  [[ -n "$label" ]] || return 1
  printf '%s\n' "$label"
}

# hm_gen_resolve PROFILE GENERATION
# Resolve a local generation number inside PROFILE and print the internal
# identifier. An unknown number prints nothing and returns 1. A malformed
# number is a usage error, a database error aborts the command.
hm_gen_resolve() {
  local profile="$1" generation="$2" id

  [[ "$generation" =~ ^[0-9]+$ ]] ||
    hm_die "$HM_EX_USAGE" "Generation numbers must be positive integers: $generation"

  id="$(hm_db_scalar "
    SELECT g.id
      FROM generations g
      JOIN profiles pr ON pr.id = g.profile_id
     WHERE pr.name = $(hm_sql_quote "$profile")
       AND g.number = $generation;")" ||
    hm_die "$HM_EX_DB" "Cannot read the generation $generation from the database."

  [[ -n "$id" ]] || return 1
  printf '%s\n' "$id"
}

# hm_gen_require PROFILE GENERATION
# Resolve a local number and abort with a state error when PROFILE does not
# contain it. Print the internal identifier.
hm_gen_require() {
  local profile="$1" generation="$2" id status

  status=0
  id="$(hm_gen_resolve "$profile" "$generation")" || status=$?
  if (( status != 0 && status != 1 )); then
    return "$status"
  fi

  [[ -n "$id" ]] ||
    hm_die "$HM_EX_STATE" "There is no generation $generation in the profile $profile."

  printf '%s\n' "$id"
}

# hm_gen_set_selected GENERATION_ID [PROFILE]
# Record the selection. With a profile the selection of the profile is
# written and the global selection follows it, so that "hm discard" can
# always restore the generation that was switched to last.
hm_gen_set_selected() {
  local id profile="${2:-}" sql
  id="$(hm_sql_int "$1")"

  sql="INSERT INTO state (key, value) VALUES"
  if [[ -n "$profile" ]]; then
    sql+=" ($(hm_sql_quote "$(hm_profile_state_key "$profile")"), $(hm_sql_quote "$id")),"
  fi
  sql+=" ('selected_generation', $(hm_sql_quote "$id"))
        ON CONFLICT(key) DO UPDATE SET value = excluded.value;"

  hm_db_exec "$sql"
}

# hm_gen_exists GENERATION_ID
hm_gen_exists() {
  local id count
  id="$(hm_sql_int "$1")"

  count="$(hm_db_scalar "SELECT COUNT(*) FROM generations WHERE id = $id;")" ||
    hm_die "$HM_EX_DB" "Cannot read the generations from the database."

  [[ "$count" != "0" ]]
}

# hm_gen_entry_count GENERATION_ID
hm_gen_entry_count() {
  local id
  id="$(hm_sql_int "$1")"
  hm_db_scalar "SELECT COUNT(*) FROM generation_entries WHERE generation_id = $id;"
}

# hm_gen_object_count GENERATION_ID - number of distinct content objects
# referenced by a generation.
hm_gen_object_count() {
  local id
  id="$(hm_sql_int "$1")"
  hm_db_scalar "SELECT COUNT(DISTINCT file_id) FROM generation_entries WHERE generation_id = $id AND file_id IS NOT NULL;"
}

# hm_gen_entries GENERATION_ID VARIABLE
# Store one line per generation entry in VARIABLE. The fields are separated
# by HM_FIELD_SEP:
#   hex(path) entry_type hex(hash) mode uid gid mtime size
# The path and the hash are hex encoded so that any byte survives the
# round trip through the result format.
#
# The function fails with HM_EX_DB when the query fails, an empty result
# and a failed query are never confused with each other.
hm_gen_entries() {
  local id
  # The nameref writes into the variable of the caller, shellcheck cannot
  # see through it.
  # shellcheck disable=SC2034
  local -n hm__entries_ref="$2"

  id="$(hm_sql_int "$1")"

  # shellcheck disable=SC2034
  hm__entries_ref="$(hm_db_query "
    SELECT hex(p.path),
           ge.entry_type,
           hex(COALESCE(f.hash, '')),
           ge.mode,
           ge.owner_uid,
           ge.group_gid,
           ge.mtime,
           ge.size
      FROM generation_entries ge
      JOIN paths p ON p.id = ge.path_id
      LEFT JOIN files f ON f.id = ge.file_id
     WHERE ge.generation_id = $id
     ORDER BY p.path;")" || return "$HM_EX_DB"

  return 0
}

# hm_gen_missing_objects GENERATION_ID VARIABLE
# Store the hashes of the objects a generation needs but that are missing
# from the content store in VARIABLE, one hash per line.
hm_gen_missing_objects() {
  local id
  local -n hm__missing_ref="$2"
  local rows row encoded hash

  id="$(hm_sql_int "$1")"
  hm__missing_ref=""

  rows="$(hm_db_query "
    SELECT hex(f.hash)
      FROM generation_entries ge
      JOIN files f ON f.id = ge.file_id
     WHERE ge.generation_id = $id
     ORDER BY f.hash;")" || return "$HM_EX_DB"

  while IFS= read -r row; do
    [[ -n "$row" ]] || continue
    encoded="${row%%"$HM_FIELD_SEP"*}"
    hm_hex_decode hash "$encoded"
    if ! hm_store_has "$hash"; then
      hm__missing_ref+="$hash"$'\n'
    fi
  done <<< "$rows"

  return 0
}

# hm_gen_materialize GENERATION_ID TARGET_DIR
# Write the content of a generation into TARGET_DIR. The directory must be
# empty, the caller creates it.
#
# The materialization runs in three passes. The directory tree is created
# first, the content is written afterwards and the recorded modes of the
# directories are applied at the very end. A directory that is recorded
# without write permission therefore never blocks the creation of its own
# children.
hm_gen_materialize() {
  local id="$1" target="$2"
  local rows row encoded entry_type hash_hex hash mode mtime
  local path dest parent
  local -a e_path=() e_type=() e_hash=() e_mode=() e_mtime=()
  local index=0

  if ! hm_gen_entries "$id" rows; then
    hm_log_error "Cannot read the entries of the generation $id."
    return "$HM_EX_DB"
  fi

  while IFS= read -r row; do
    [[ -n "$row" ]] || continue
    IFS="$HM_FIELD_SEP" read -r encoded entry_type hash_hex mode _uid _gid mtime _size <<< "$row"

    e_path[index]="$encoded"
    e_type[index]="$entry_type"
    e_hash[index]="$hash_hex"
    e_mode[index]="$mode"
    e_mtime[index]="$mtime"
    index=$((index + 1))
  done <<< "$rows"

  # Pass 1, the directory tree.
  for ((index = 0; index < ${#e_path[@]}; index++)); do
    hm_hex_decode path "${e_path[$index]}"
    dest="$target$path"

    if [[ "${e_type[$index]}" == "dir" ]]; then
      mkdir -p -- "$dest" || return "$HM_EX_IO"
    else
      parent="${dest%/*}"
      [[ "$parent" == "$dest" ]] && parent="/"
      mkdir -p -- "$parent" || return "$HM_EX_IO"
    fi
  done

  # Pass 2, the content.
  for ((index = 0; index < ${#e_path[@]}; index++)); do
    [[ "${e_type[$index]}" == "file" ]] || continue

    hm_hex_decode path "${e_path[$index]}"
    hm_hex_decode hash "${e_hash[$index]}"
    dest="$target$path"

    if [[ ! -f "$(hm_store_path "$hash")" ]]; then
      hm_log_error "Missing content object for $(hm_path_display "$path"): $hash"
      return "$HM_EX_STORE"
    fi

    cp -- "$(hm_store_path "$hash")" "$dest" || return "$HM_EX_IO"
    chmod "$(hm_mode_to_octal "${e_mode[$index]}")" -- "$dest" 2>/dev/null || true
    touch -d "@${e_mtime[$index]}" -- "$dest" 2>/dev/null || true
  done

  # Pass 3, the recorded modes of the directories.
  for ((index = 0; index < ${#e_path[@]}; index++)); do
    [[ "${e_type[$index]}" == "dir" ]] || continue

    hm_hex_decode path "${e_path[$index]}"
    dest="$target$path"
    chmod "$(hm_mode_to_octal "${e_mode[$index]}")" -- "$dest" 2>/dev/null || true
  done

  return 0
}
