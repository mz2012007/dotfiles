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

# hm_gen_selected - print the id of the selected generation, if any.
hm_gen_selected() {
  hm_db_scalar "SELECT value FROM state WHERE key = 'selected_generation';"
}

# hm_gen_latest - print the id of the newest generation.
# The order is created_at DESC, id DESC, the identifier alone is not an
# order because it does not reflect the creation time.
hm_gen_latest() {
  hm_db_scalar "SELECT id FROM generations ORDER BY created_at DESC, id DESC LIMIT 1;"
}

# hm_gen_set_selected GENERATION_ID
hm_gen_set_selected() {
  local id
  id="$(hm_sql_int "$1")"

  hm_db_exec "INSERT INTO state (key, value) VALUES ('selected_generation', $(hm_sql_quote "$id"))
              ON CONFLICT(key) DO UPDATE SET value = excluded.value;"
}

# hm_gen_clear_selected
hm_gen_clear_selected() {
  hm_db_exec "DELETE FROM state WHERE key = 'selected_generation';"
}

# hm_gen_exists GENERATION_ID
hm_gen_exists() {
  local id count
  id="$(hm_sql_int "$1")"
  count="$(hm_db_scalar "SELECT COUNT(*) FROM generations WHERE id = $id;")"
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

# hm_gen_entries GENERATION_ID
# Print one line per generation entry. The fields are separated by
# HM_FIELD_SEP:
#   hex(path) entry_type hex(hash) mode uid gid mtime size
# The path and the hash are hex encoded so that any byte survives the
# round trip through the result format.
hm_gen_entries() {
  local id
  id="$(hm_sql_int "$1")"

  hm_db_query "
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
     ORDER BY p.path;"
}

# hm_gen_missing_objects GENERATION_ID
# Print the hashes of the objects a generation needs but that are missing
# from the content store.
hm_gen_missing_objects() {
  local id
  id="$(hm_sql_int "$1")"

  hm_db_query "
    SELECT hex(f.hash)
      FROM generation_entries ge
      JOIN files f ON f.id = ge.file_id
     WHERE ge.generation_id = $id
     ORDER BY f.hash;" |
    while IFS= read -r row; do
      local encoded="${row%%"$HM_FIELD_SEP"*}"
      local hash
      hm_hex_decode hash "$encoded"
      if ! hm_store_has "$hash"; then
        printf '%s\n' "$hash"
      fi
    done
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
  local row encoded entry_type hash_hex hash mode uid gid mtime size
  local path dest parent
  local -a e_path=() e_type=() e_hash=() e_mode=() e_mtime=()
  local index=0

  while IFS= read -r row; do
    [[ -n "$row" ]] || continue
    IFS="$HM_FIELD_SEP" read -r encoded entry_type hash_hex mode uid gid mtime size <<< "$row"

    e_path[$index]="$encoded"
    e_type[$index]="$entry_type"
    e_hash[$index]="$hash_hex"
    e_mode[$index]="$mode"
    e_mtime[$index]="$mtime"
    index=$((index + 1))
  done < <(hm_gen_entries "$id")

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
