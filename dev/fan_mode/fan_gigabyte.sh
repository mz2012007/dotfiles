#!/usr/bin/env bash
set -Eeuo pipefail

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/fan-cycle"
LOG_FILE="$STATE_DIR/debug.log"

mkdir -p "$STATE_DIR"
exec >>"$LOG_FILE" 2>&1

log() {
  printf '[%s] %s\n' "$(date '+%F %T')" "$*"
}

notify() {
  if command -v notify-send >/dev/null 2>&1; then
    notify-send "Fan Control" "$1" || true
  fi
}

log "Script started"

# Read the current mode and change it using one pkexec invocation.
if ! result="$(pkexec /usr/local/libexec/fan-mode-helper cycle)"; then
  log "ERROR: Fan mode operation failed"
  notify "Failed to change fan mode. Check debug.log"
  exit 1
fi

read -r current next_mode <<<"$result"

if [[ -z "${current:-}" || -z "${next_mode:-}" ]]; then
  log "ERROR: Invalid helper output: $result"
  notify "Invalid helper response. Check debug.log"
  exit 1
fi

log "Current mode: $current"
log "Setting mode: $next_mode"
log "Mode changed successfully"

notify "$current → $next_mode"
