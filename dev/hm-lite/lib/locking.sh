#!/usr/bin/env bash
#
# lib/locking.sh - project lock.
#
# Every command that mutates the project state takes an exclusive lock.
# Read only commands take a shared lock. The lock is implemented with
# flock(2) on a lock file that lives inside the project directory, so the
# operating system releases it automatically when a process dies.
#
# The file only defines functions. Sourcing it has no side effects.
#

# hm_lock_acquire MODE
# MODE is "exclusive" or "shared". The lock file descriptor stays open for
# the lifetime of the process, the operating system releases the lock when
# the process terminates.
hm_lock_acquire() {
  local mode="${1:-exclusive}"
  local lock_file="${HM_LOCK_FILE:-$HM_DIR/hm.lock}"
  local timeout="${HM_LOCK_TIMEOUT:-10}"
  local flags="-x"

  if [[ "$mode" == "shared" ]]; then
    flags="-s"
  fi

  if [[ ! -d "$HM_DIR" ]]; then
    hm_die "$HM_EX_VALIDATION" "Project directory not found: $HM_DIR"
  fi

  if ! exec {HM_LOCK_FD}>>"$lock_file"; then
    hm_die "$HM_EX_IO" "Cannot open the lock file: $lock_file"
  fi
  chmod 600 -- "$lock_file" 2>/dev/null || true

  if ! flock -w "$timeout" "$flags" "$HM_LOCK_FD"; then
    exec {HM_LOCK_FD}>&-
    hm_die "$HM_EX_LOCK" "Another HM-Lite process holds the project lock (waited ${timeout}s)."
  fi

  hm_log_debug "Acquired $mode project lock."
  return 0
}
