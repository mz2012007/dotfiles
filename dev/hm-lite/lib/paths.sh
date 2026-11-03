#!/usr/bin/env bash
#
# lib/paths.sh - path normalization and validation.
#
# HM-Lite stores absolute, lexically normalized paths. The normalization is
# purely lexical on purpose: symbolic links are never resolved, because
# resolving them would change which filesystem object the user asked to
# track. A user that names ~/.config/kitty where .config is a symlink keeps
# tracking that exact path.
#
# The file only defines functions. Sourcing it has no side effects.
#

# hm_path_normalize PATH
# Return the absolute, lexically normalized form of PATH.
#   * relative paths are resolved against the current working directory
#   * "." and empty components are removed
#   * ".." removes the previous component but never escapes the root
#   * repeated and trailing slashes are collapsed
#   * symbolic links are NOT resolved
# The result is printed without a trailing newline. Returns 1 for an empty
# input.
hm_path_normalize() {
  local input="$1"
  local rest part
  local -a stack=()

  [[ -n "$input" ]] || return 1

  [[ "$input" == /* ]] || input="$PWD/$input"

  rest="$input"
  while [[ -n "$rest" ]]; do
    if [[ "$rest" == */* ]]; then
      part="${rest%%/*}"
      rest="${rest#*/}"
    else
      part="$rest"
      rest=""
    fi

    case "$part" in
      '' | '.')
        ;;
      '..')
        if [[ ${#stack[@]} -gt 0 ]]; then
          unset 'stack[-1]'
        fi
        ;;
      *)
        stack+=("$part")
        ;;
    esac
  done

  local out=''
  for part in "${stack[@]}"; do
    out+="/$part"
  done

  printf '%s\n' "${out:-/}"
}

# hm_path_is_under ROOT PATH
# Return 0 when PATH is ROOT itself or is located inside ROOT. Both
# arguments are expected to be normalized already.
hm_path_is_under() {
  local root="${1%/}"
  local path="$2"

  [[ -n "$root" ]] || root="/"

  if [[ "$root" == "/" ]]; then
    [[ "$path" == /* ]]
    return $?
  fi

  [[ "$path" == "$root" || "$path" == "$root/"* ]]
}

# hm_path_join BASE RELATIVE
# Join a normalized base directory with a relative component.
hm_path_join() {
  local base="$1" rest="$2"

  if [[ "$base" == "/" ]]; then
    printf '/%s\n' "${rest#/}"
  else
    printf '%s/%s\n' "${base%/}" "${rest#/}"
  fi
}

# hm_path_basename PATH
hm_path_basename() {
  local path="$1"
  printf '%s\n' "${path##*/}"
}

# hm_path_dirname PATH
hm_path_dirname() {
  local path="$1"
  if [[ "$path" == */* && "$path" != /* ]]; then
    printf '%s\n' "${path%/*}"
  elif [[ "$path" == /* ]]; then
    printf '/\n'
  else
    printf '.\n'
  fi
}

# hm_path_display PATH
# Render a path for a single line log message. Control characters are
# escaped so that a log line is never broken by a hostile file name.
hm_path_display() {
  local path="$1"
  path="${path//$'\n'/\\n}"
  path="${path//$'\t'/\\t}"
  path="${path//$'\r'/\\r}"
  printf '%s' "$path"
}

# hm_path_in_home PATH
# Return 0 when PATH is located inside the current user home directory.
hm_path_in_home() {
  local path="$1"
  local home="${HOME%/}"

  [[ -n "$home" ]] || return 1
  hm_path_is_under "$home" "$path"
}

# hm_path_is_safe_target PATH
# Return 0 when PATH may be used as a destination for a managed operation.
# The path must be absolute and must not be the filesystem root.
hm_path_is_safe_target() {
  local path="$1"

  [[ "$path" == /* ]] || return 1
  [[ "$path" != "/" ]] || return 1
  return 0
}
