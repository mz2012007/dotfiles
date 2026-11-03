#!/usr/bin/env bash
#
# lib/storage.sh - content addressable store.
#
# Layout:
#   <runtime>/store/objects/<2 hex characters>/<full sha256 hash>
#
# The two character prefix keeps the number of entries per directory low.
# The full hash is the identity of an object.
#
# Objects are immutable. A stored object is never modified in place, it is
# only created and removed. A write to a materialized copy in current/ or
# testing/ therefore can never change historical content.
#
# The file only defines functions. Sourcing it has no side effects.
#

# hm_store_root - root directory of the content store.
hm_store_root() {
  printf '%s\n' "${HM_STORE_ROOT:-$HM_DIR/store/objects}"
}

# hm_store_prefix_len - number of hash characters used as directory prefix.
hm_store_prefix_len() {
  printf '%s\n' "${HM_STORE_PREFIX_LEN:-2}"
}

# hm_store_path HASH
# Print the absolute path of the object with the given hash.
hm_store_path() {
  local hash="$1"
  local prefix_len
  prefix_len="$(hm_store_prefix_len)"

  printf '%s/%s/%s\n' "$(hm_store_root)" "${hash:0:prefix_len}" "$hash"
}

# hm_store_has HASH
# Return 0 when the object exists in the store.
hm_store_has() {
  local hash="$1"
  local path
  path="$(hm_store_path "$hash")"
  [[ -f "$path" ]]
}

# hm_store_verify HASH
# Return 0 when the stored object exists and its content still hashes to
# HASH. The verification reads the whole object.
hm_store_verify() {
  local hash="$1"
  local path
  path="$(hm_store_path "$hash")"

  [[ -f "$path" ]] || return 1
  hm_hash_matches_file "$hash" "$path"
}

# hm_store_put SOURCE HASH
# Copy SOURCE into the store under HASH. The source is verified before and
# after the copy, the object is written to a temporary file first and then
# moved into place with a rename, so an object is never visible in a
# partially written state.
hm_store_put() {
  local source="$1" hash="$2"
  local target dir prefix_len actual tmp

  hm_is_sha256 "$hash" || {
    hm_die "$HM_EX_STORE" "Invalid content hash: $hash"
  }

  target="$(hm_store_path "$hash")"
  prefix_len="$(hm_store_prefix_len)"
  dir="${target%/*}"

  # An existing object is reused, but only after it was verified.
  if [[ -f "$target" ]]; then
    if hm_store_verify "$hash"; then
      return 0
    fi
    hm_log_warn "Replacing a corrupted store object: $(hm_path_display "$target")"
    rm -f -- "$target"
  fi

  actual="$(hm_sha256_file "$source")" || {
    hm_die "$HM_EX_STORE" "Cannot read the source file: $(hm_path_display "$source")"
  }
  if [[ "$actual" != "$hash" ]]; then
    hm_die "$HM_EX_STORE" "Source file does not match the expected hash for $hash"
  fi

  mkdir -p -- "$dir" || hm_die "$HM_EX_IO" "Cannot create the store directory: $dir"
  chmod 700 -- "$dir" 2>/dev/null || true

  tmp="$(mktemp -- "$dir/.incoming.XXXXXXXX")" || hm_die "$HM_EX_IO" "Cannot create a staging file in $dir"
  chmod 600 -- "$tmp" 2>/dev/null || true

  if ! cat -- "$source" > "$tmp"; then
    rm -f -- "$tmp"
    hm_die "$HM_EX_IO" "Cannot copy the content into the store"
  fi

  actual="$(hm_sha256_file "$tmp")" || {
    rm -f -- "$tmp"
    hm_die "$HM_EX_STORE" "Cannot verify the staged store object"
  }
  if [[ "$actual" != "$hash" ]]; then
    rm -f -- "$tmp"
    hm_die "$HM_EX_STORE" "The staged store object does not match hash $hash"
  fi

  mv -f -- "$tmp" "$target" || {
    rm -f -- "$tmp"
    hm_die "$HM_EX_IO" "Cannot move the object into the store"
  }
  chmod 400 -- "$target" 2>/dev/null || true

  return 0
}

# hm_store_object_hashes
# Print the hash of every object in the store, one per line. Only files
# whose name is a valid SHA-256 hash are reported, everything else is
# ignored so that a malformed store cannot confuse the caller.
hm_store_object_hashes() {
  local root prefix_len
  root="$(hm_store_root)"
  prefix_len="$(hm_store_prefix_len)"

  [[ -d "$root" ]] || return 0

  while IFS= read -r -d '' file; do
    local name="${file##*/}"
    if [[ ${#name} -eq 64 ]] && hm_is_sha256 "$name"; then
      printf '%s\n' "$name"
    fi
  done < <(find "$root" -mindepth 2 -maxdepth 2 -type f -name '*' -print0 2>/dev/null)
}

# hm_store_remove HASH
# Remove a single object from the store. The path is rebuilt from the hash
# and validated, therefore a caller cannot remove anything else.
hm_store_remove() {
  local hash="$1"
  local path dir

  hm_is_sha256 "$hash" || return 1
  path="$(hm_store_path "$hash")"
  dir="${path%/*}"

  [[ -f "$path" ]] || return 1
  rm -f -- "$path" || return 1

  # Remove the prefix directory when it became empty.
  rmdir -- "$dir" 2>/dev/null || true

  return 0
}

# hm_store_count - print the number of objects in the store.
hm_store_count() {
  local count=0
  local hash
  while IFS= read -r hash; do
    [[ -n "$hash" ]] && count=$((count + 1))
  done < <(hm_store_object_hashes)
  printf '%d\n' "$count"
}

# hm_store_total_size - print the summed size of all objects in bytes.
hm_store_total_size() {
  local total=0
  local path hash
  while IFS= read -r hash; do
    [[ -n "$hash" ]] || continue
    path="$(hm_store_path "$hash")"
    if [[ -f "$path" ]]; then
      local size
      size="$(stat -c '%s' -- "$path" 2>/dev/null || printf '0')"
      total=$((total + size))
    fi
  done < <(hm_store_object_hashes)
  printf '%d\n' "$total"
}
