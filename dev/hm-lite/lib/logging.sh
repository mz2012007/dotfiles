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
HM_C_RED=''
HM_C_GREEN=''
HM_C_YELLOW=''
HM_C_BLUE=''
HM_C_CYAN=''
HM_C_BOLD=''
HM_LOG_LEVEL="INFO"
HM_LOG_FILE="1"

# hm_log_init
# Prepare the colour palette. Colours are disabled automatically when the
# output is not a terminal and when HM_COLOR disables them explicitly.
hm_log_init() {
  local mode="${HM_COLOR:-auto}"

  case "$mode" in
    0 | no | never | off) mode="never" ;;
    1 | yes | always | on) mode="always" ;;
    *) mode="auto" ;;
  esac

  if [[ "$mode" == "always" ]] || { [[ "$mode" == "auto" ]] && [[ -t 1 ]]; }; then
    HM_C_RESET=$'\033[0m'
    HM_C_RED=$'\033[31m'
    HM_C_GREEN=$'\033[32m'
    HM_C_YELLOW=$'\033[33m'
    HM_C_BLUE=$'\033[34m'
    HM_C_CYAN=$'\033[36m'
    HM_C_BOLD=$'\033[1m'
  else
    HM_C_RESET=''
    HM_C_RED=''
    HM_C_GREEN=''
    HM_C_YELLOW=''
    HM_C_BLUE=''
    HM_C_CYAN=''
    HM_C_BOLD=''
  fi

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

# hm_log_plain MESSAGE
# Print a message without a level prefix. Used for help text.
hm_log_plain() {
  printf '%s\n' "$*"
}
