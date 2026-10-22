#!/usr/bin/env bash
#
# lib/common.sh - shared helpers.
#
# Provides: exit codes, fatal error reporting, external command checks,
# user confirmation, secure temporary files, time helpers and the
# configuration file parser.
#
# The file only defines functions. Sourcing it has no side effects.
#

# --- Exit codes -----------------------------------------------------------
# The exit codes are part of the public interface of HM-Lite and are
# documented in docs/commands.md.
HM_EX_OK=0          # success
HM_EX_ERROR=1       # generic runtime failure
HM_EX_USAGE=2       # invalid command line usage
HM_EX_VALIDATION=3  # validation or precondition failure
HM_EX_STATE=4       # inconsistent state (for example a vanished source path)
HM_EX_DB=5          # database failure
HM_EX_STORE=6       # content store failure
HM_EX_DECLINED=7    # the user declined a confirmation
HM_EX_LOCK=8        # the project lock could not be acquired
HM_EX_IO=9          # filesystem or input/output failure

# --- Errors ---------------------------------------------------------------

# hm_die EXIT_CODE MESSAGE...
# Print the message to stderr and terminate the process.
hm_die() {
  local code="$1"
  shift
  printf '[ERROR] %s\n' "$*" >&2
  exit "$code"
}

# --- External commands ----------------------------------------------------

# hm_require_cmd NAME...
# Fail with a clear message when a required external command is missing.
hm_require_cmd() {
  local cmd
  for cmd in "$@"; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      hm_die "$HM_EX_VALIDATION" "Required command not found: $cmd"
    fi
  done
}

# --- Time -----------------------------------------------------------------

# hm_now_epoch - current unix timestamp in seconds.
hm_now_epoch() {
  date +%s
}

# hm_now_utc - current UTC time in ISO 8601 format.
hm_now_utc() {
  date -u +%Y-%m-%dT%H:%M:%SZ
}

# hm_format_epoch SECONDS
# Print a unix timestamp in ISO 8601 format.
hm_format_epoch() {
  local value="${1:-}"

  [[ "$value" =~ ^[0-9]+$ ]] || return 1

  date -u -d "@$value" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null
}

# hm_utc_stamp - compact UTC timestamp, safe for file names.
hm_utc_stamp() {
  date -u +%Y%m%dT%H%M%SZ
}

# --- File modes ------------------------------------------------------------

# hm_mode_to_decimal OCTAL
# Convert an octal mode such as 644 into its decimal representation. The
# database stores the mode as a decimal integer, the shell tools want the
# octal notation.
hm_mode_to_decimal() {
  local value="${1:-}"

  [[ "$value" =~ ^[0-7]+$ ]] || return 1
  value="${value#"${value%%[!0]*}"}"
  [[ -n "$value" ]] || value=0

  printf '%d' "$((8#$value))"
}

# hm_mode_to_octal DECIMAL
# Convert a decimal mode back into the octal notation.
hm_mode_to_octal() {
  local value="${1:-}"

  [[ "$value" =~ ^[0-9]+$ ]] || return 1

  printf '%o' "$value"
}

# --- Safe removal ----------------------------------------------------------

# hm_rm_rf_under BASE TARGET
# Remove TARGET recursively, but only when TARGET is located inside BASE and
# is not BASE itself. Every other request is refused. The function is the
# only place in HM-Lite that removes a directory tree, the caller therefore
# cannot accidentally delete an arbitrary path.
hm_rm_rf_under() {
  local base="${1%/}" target="${2:-}"

  [[ -n "$base" && -n "$target" ]] || return 1
  [[ "$target" != "$base" ]] || return 1
  [[ "$target" == "$base/"* ]] || return 1

  rm -rf -- "$target"
}

# --- Temporary files ------------------------------------------------------

# hm_mktemp_dir [TEMPLATE]
# Create a private temporary directory inside the runtime tmp directory.
hm_mktemp_dir() {
  local template="${1:-tmp.XXXXXXXX}"
  local base="${HM_TMP_DIR:-$HM_DIR/tmp}"
  local dir

  mkdir -p -- "$base" 2>/dev/null || true
  dir="$(mktemp -d -- "$base/$template" 2>/dev/null)" || return "$HM_EX_IO"
  chmod 700 -- "$dir" 2>/dev/null || true
  printf '%s\n' "$dir"
}

# hm_mktemp_file [TEMPLATE]
# Create a private temporary file inside the runtime tmp directory.
hm_mktemp_file() {
  local template="${1:-tmp.XXXXXXXX}"
  local base="${HM_TMP_DIR:-$HM_DIR/tmp}"
  local file

  mkdir -p -- "$base" 2>/dev/null || true
  file="$(mktemp -- "$base/$template" 2>/dev/null)" || return "$HM_EX_IO"
  chmod 600 -- "$file" 2>/dev/null || true
  printf '%s\n' "$file"
}

# --- Confirmation ---------------------------------------------------------

# hm_confirm PROMPT
# Ask the user a yes/no question. Reads the answer from standard input so
# that the behaviour stays testable. Returns 0 for "yes", 1 for "no".
# A closed or exhausted standard input is treated as "no".
hm_confirm() {
  local prompt="$1"
  local reply=""

  printf '%s ' "$prompt" >&2
  if ! IFS= read -r reply; then
    printf '\n' >&2
    return 1
  fi

  case "$reply" in
    y | Y | yes | YES | Yes) return 0 ;;
    *) return 1 ;;
  esac
}

# --- Configuration --------------------------------------------------------

# Configuration keys that may appear in the configuration file. Any other
# key is rejected so that a corrupted file cannot silently change behaviour.
HM_CONFIG_KEYS=(
  HM_LOG_LEVEL
  HM_LOG_FILE
  HM_COLOR
  HM_HASH_ALGORITHM
  HM_STORE_PREFIX_LEN
  HM_LOCK_TIMEOUT
  HM_ALLOW_OUTSIDE_HOME
)

# hm_config_load FILE
# Parse a KEY=VALUE configuration file as *data*. The file is never executed,
# it is not sourced, therefore it cannot run arbitrary code. Missing files
# are not an error, malformed lines are reported and ignored.
#
# A value that is already present in the environment wins over the file. The
# environment is the more specific instruction of the user.
hm_config_load() {
  local file="$1"
  local line key value

  [[ -f "$file" ]] || return 0
  [[ -r "$file" ]] || {
    hm_warn "Configuration file is not readable: $file"
    return 0
  }

  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%$'\r'}"
    # Skip blank lines and comments.
    [[ -z "${line//[[:space:]]/}" ]] && continue
    [[ "${line#"${line%%[![:space:]]*}"}" == \#* ]] && continue
    [[ "$line" != *=* ]] && {
      hm_warn "Ignoring malformed configuration line: $line"
      continue
    }

    key="${line%%=*}"
    value="${line#*=}"

    # Trim surrounding whitespace from the key.
    key="${key#"${key%%[![:space:]]*}"}"
    key="${key%"${key##*[![:space:]]}"}"

    if ! hm_config_key_known "$key"; then
      hm_warn "Ignoring unknown configuration key: $key"
      continue
    fi

    if hm_config_key_from_environment "$key"; then
      hm_log_debug "Keeping the environment value of $key."
      continue
    fi

    printf -v "$key" '%s' "$value"
  done < "$file"

  return 0
}

# hm_config_key_from_environment KEY
# Return 0 when KEY was present in the environment of the process.
hm_config_key_from_environment() {
  local candidate="$1" name

  for name in "${HM_ENV_KEYS[@]:-}"; do
    if [[ "$name" == "$candidate" ]]; then
      return 0
    fi
  done

  return 1
}

# hm_config_key_known KEY
hm_config_key_known() {
  local candidate="$1" known
  for known in "${HM_CONFIG_KEYS[@]}"; do
    if [[ "$candidate" == "$known" ]]; then
      return 0
    fi
  done
  return 1
}

# hm_config_get KEY DEFAULT
hm_config_get() {
  local key="$1" fallback="$2"
  printf '%s\n' "${!key:-$fallback}"
}
