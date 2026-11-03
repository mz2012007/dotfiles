#!/usr/bin/env bash
# update-system.sh - Modular system updater for Void Linux
# Usage: update-system.sh [--all|--list|MODULE...|--help]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load shared helpers
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

# ============ Module Registry ============
# Order matters for --all.
MODULES=(
  "brave"
  "hyprland"
  "dms"
  "system"
  "dust"
  "artcraft"
  "opencode-desktop"
)

# ============ Dispatcher ============
load_module() {
  local name="$1"
  local path="$SCRIPT_DIR/modules/${name}.sh"
  if [[ ! -f "$path" ]]; then
    fail "Module file not found: $path"
    return 1
  fi
  # shellcheck disable=SC1090
  source "$path"
}

run_module() {
  local name="$1"
  local fn="module_${name}_update"
  if ! declare -F "$fn" >/dev/null; then
    fail "Module '$name' does not define $fn()"
    return 1
  fi
  "$fn"
}

module_exists() {
  local name="$1" m
  for m in "${MODULES[@]}"; do
    [[ "$m" == "$name" ]] && return 0
  done
  return 1
}

usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTION|MODULE...]

Options:
  --all       Run all enabled modules
  --list      List enabled modules
  -h, --help  Show this help

Modules:
$(printf '  %-12s\n' "${MODULES[@]}")

Examples:
  $(basename "$0") --all
  $(basename "$0") brave
  $(basename "$0") brave system
EOF
}

run_modules() {
  local failed=0 m
  for m in "$@"; do
    load_module "$m" || {
      failed=1
      continue
    }
    run_module "$m" || failed=1
  done
  return "$failed"
}

main() {
  if [[ $EUID -eq 0 ]]; then
    fail "Do not run as root. Script will prompt for sudo when needed."
    exit 1
  fi

  if [[ $# -eq 0 ]]; then
    usage
    exit 0
  fi

  case "$1" in
  -h | --help)
    usage
    exit 0
    ;;
  --list)
    printf '%s\n' "${MODULES[@]}"
    exit 0
    ;;
  --all)
    start_sudo_keepalive
    run_modules "${MODULES[@]}"
    ;;
  --*)
    fail "Unknown option: $1"
    usage
    exit 1
    ;;
  *)
    start_sudo_keepalive
    for m in "$@"; do
      if ! module_exists "$m"; then
        fail "Unknown module: $m (see --list)"
        exit 1
      fi
    done
    run_modules "$@"
    ;;
  esac
}

main "$@"
