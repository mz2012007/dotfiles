#!/usr/bin/env bash
#
# lib/hashing.sh - SHA-256 helpers.
#
# The content identity of a file is the SHA-256 hash of its bytes. No other
# property (path, timestamp, owner, permissions) is part of the identity.
#
# The file only defines functions. Sourcing it has no side effects.
#

# hm_sha256_file FILE
# Print the SHA-256 hash of FILE. The file name is passed to sha256sum
# after a "--" separator, therefore names that start with a dash are safe.
hm_sha256_file() {
  local file="$1"
  local line hash

  [[ -f "$file" ]] || return 1
  [[ -r "$file" ]] || return 1

  line="$(sha256sum -- "$file" 2>/dev/null)" || return 1
  hash="${line%% *}"

  printf '%s\n' "$hash"
}

# hm_sha256_stdin
# Print the SHA-256 hash of the data read from standard input.
hm_sha256_stdin() {
  local line hash

  line="$(sha256sum 2>/dev/null)" || return 1
  hash="${line%% *}"

  printf '%s\n' "$hash"
}

# hm_is_sha256 VALUE
# Return 0 when VALUE is a lower case hexadecimal SHA-256 hash.
hm_is_sha256() {
  [[ "$1" =~ ^[0-9a-f]{64}$ ]]
}

# hm_hash_matches_file HASH FILE
# Return 0 when FILE currently hashes to HASH.
hm_hash_matches_file() {
  local expected="$1" file="$2"
  local actual

  actual="$(hm_sha256_file "$file")" || return 1
  [[ "$actual" == "$expected" ]]
}
