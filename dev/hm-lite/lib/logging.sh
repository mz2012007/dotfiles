#!/usr/bin/env bash
#
# lib/logging.sh - logging and coloured output.
#
# Levels: ERROR, WARN, INFO, DEBUG. The verbosity is controlled by the
# HM_LOG_LEVEL configuration key. Diagnostics always go to standard error so
# that command output on standard output stays machine readable.
#
# File logging appends to <runtime>/logs/hm.log. The append is a single
# write to a file opened in append mode, therefore it does not block the
# caller and it never interleaves partial lines between processes.
#
# The file only defines functions. Sourcing it has no side effects.
#

# --- Colours --------------------------------------------------------------

# Defaults, replaced by hm_log_init. They exist so that the logging helpers
# can be used before the initialisation ran.
HM_C_RESET=''
# shellcheck disable=SC2034
HM_C_BOLD=''
HM_C_RED=''
HM_C_GREEN=''
HM_C_YELLOW=''
HM_C_BLUE=''
HM_C_CYAN=''
# The palette of the human readable output on standard output. It is
# decided separately from the diagnostic palette: a redirected standard
# output never colours the table and a redirected standard error never
# colours the diagnostics.
# shellcheck disable=SC2034
HM_C_OUT_RESET=''
# shellcheck disable=SC2034
HM_C_OUT_BOLD=''
# shellcheck disable=SC2034
HM_C_OUT_RED=''
# shellcheck disable=SC2034
HM_C_OUT_GREEN=''
# shellcheck disable=SC2034
HM_C_OUT_YELLOW=''
# shellcheck disable=SC2034
HM_C_OUT_BLUE=''
# shellcheck disable=SC2034
HM_C_OUT_CYAN=''
HM_LOG_LEVEL="${HM_LOG_LEVEL:-INFO}"
HM_LOG_FILE="${HM_LOG_FILE:-1}"

# _hm_color_mode - print the effective colour mode: never, always or auto.
# A non-empty NO_COLOR disables the colours regardless of HM_COLOR, an empty
# NO_COLOR counts as unset, as the convention requires.
_hm_color_mode() {
  local mode="${HM_COLOR:-auto}"

  if [[ -n "${NO_COLOR:-}" ]]; then
    printf 'never'
    return 0
  fi

  case "$mode" in
    0 | no | never | off) printf 'never' ;;
    1 | yes | always | on) printf 'always' ;;
    *) printf 'auto' ;;
  esac
}

# hm_color_palette PREFIX FD
# Fill the palette variables PREFIX_RESET, PREFIX_BOLD, ... for the stream
# FD. Colours are disabled automatically when the stream is not a terminal
# and when HM_COLOR or NO_COLOR disables them.
hm_color_palette() {
  local prefix="$1" fd="$2" mode
  local reset='' bold='' red='' green='' yellow='' blue='' cyan=''

  mode="$(_hm_color_mode)"

  if [[ "$mode" == "always" ]] || { [[ "$mode" == "auto" ]] && [[ -t "$fd" ]]; }; then
    reset=$'\033[0m'
    bold=$'\033[1m'
    red=$'\033[31m'
    green=$'\033[32m'
    yellow=$'\033[33m'
    blue=$'\033[34m'
    cyan=$'\033[36m'
  fi

  # The palette lives in the caller, shellcheck cannot see the indirection.
  # shellcheck disable=SC2034
  printf -v "${prefix}_RESET" '%s' "$reset"
  # shellcheck disable=SC2034
  printf -v "${prefix}_BOLD" '%s' "$bold"
  # shellcheck disable=SC2034
  printf -v "${prefix}_RED" '%s' "$red"
  # shellcheck disable=SC2034
  printf -v "${prefix}_GREEN" '%s' "$green"
  # shellcheck disable=SC2034
  printf -v "${prefix}_YELLOW" '%s' "$yellow"
  # shellcheck disable=SC2034
  printf -v "${prefix}_BLUE" '%s' "$blue"
  # shellcheck disable=SC2034
  printf -v "${prefix}_CYAN" '%s' "$cyan"
}

# hm_log_init
# Prepare the colour palettes and the logging defaults. The diagnostics are
# written to standard error, the human readable output to standard output,
# therefore each stream gets its own palette.
hm_log_init() {
  hm_color_palette HM_C 2
  hm_color_palette HM_C_OUT 1

  HM_LOG_LEVEL="${HM_LOG_LEVEL:-INFO}"
  HM_LOG_FILE="${HM_LOG_FILE:-1}"
}

# --- Log sinks ------------------------------------------------------------

# hm_log_write LEVEL MESSAGE
# Append one record to the log file when file logging is enabled. Logging
# failures never abort the running command.
hm_log_write() {
  local level="$1"
  shift
  local log_file="${HM_LOG_DIR:-$HM_DIR/logs}/hm.log"

  [[ "$HM_LOG_FILE" == "1" ]] || return 0
  [[ -d "${HM_LOG_DIR:-$HM_DIR/logs}" ]] || return 0

  printf '%s [%s] %s\n' "$(hm_now_utc)" "$level" "$*" >> "$log_file" 2>/dev/null || true
}

# hm_log_level_enabled LEVEL
hm_log_level_enabled() {
  local wanted="$1"
  local current="${HM_LOG_LEVEL:-INFO}"

  case "$current" in
    DEBUG) return 0 ;;
    INFO) [[ "$wanted" == "ERROR" || "$wanted" == "WARN" || "$wanted" == "INFO" ]] ;;
    WARN) [[ "$wanted" == "ERROR" || "$wanted" == "WARN" ]] ;;
    ERROR) [[ "$wanted" == "ERROR" ]] ;;
    *) [[ "$wanted" == "ERROR" || "$wanted" == "WARN" || "$wanted" == "INFO" ]] ;;
  esac
}

# --- Public logging helpers -----------------------------------------------

hm_log_error() {
  printf '%s[ERROR]%s %s\n' "$HM_C_RED" "$HM_C_RESET" "$*" >&2
  hm_log_write ERROR "$*"
}

hm_log_warn() {
  printf '%s[WARNING]%s %s\n' "$HM_C_YELLOW" "$HM_C_RESET" "$*" >&2
  hm_log_write WARN "$*"
}

hm_log_info() {
  printf '%s[INFO]%s %s\n' "$HM_C_BLUE" "$HM_C_RESET" "$*" >&2
  hm_log_write INFO "$*"
}

hm_log_success() {
  printf '%s[SUCCESS]%s %s\n' "$HM_C_GREEN" "$HM_C_RESET" "$*" >&2
  hm_log_write INFO "$*"
}

hm_log_debug() {
  hm_log_level_enabled DEBUG || return 0
  printf '%s[DEBUG]%s %s\n' "$HM_C_CYAN" "$HM_C_RESET" "$*" >&2
  hm_log_write DEBUG "$*"
}
