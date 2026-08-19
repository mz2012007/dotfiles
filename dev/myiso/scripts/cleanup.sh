#!/usr/bin/env bash
set -Eeuo pipefail

log() { printf '[INFO] %s\n' "$*"; }
error() { printf '[ERROR] %s\n' "$*" >&2; }

ROOT=""
DRY_RUN=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --root) ROOT="$2"; shift 2 ;;
        --dry-run) DRY_RUN=true; shift ;;
        *) error "Unknown option: $1"; exit 1 ;;
    esac
done

[[ -z "$ROOT" || ! -d "$ROOT" ]] && { error "Invalid root directory: $ROOT"; exit 1; }

if $DRY_RUN; then
    log "Would remove temporary files and caches"
    exit 0
fi

log "Cleaning up"
# Remove package cache (xbps)
rm -rf "$ROOT/var/cache/xbps" || true

# Remove temporary files
rm -rf "$ROOT/tmp/"* || true

log "Cleanup completed"
exit 0
