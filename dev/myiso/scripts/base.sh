#!/usr/bin/env bash
set -Eeuo pipefail

log() { printf '[INFO] %s\n' "$*"; }
error() { printf '[ERROR] %s\n' "$*" >&2; }

ROOT=""
REPO_URL="https://repo-default.voidlinux.org/current"
ARCH="x86_64"
DRY_RUN=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --root) ROOT="$2"; shift 2 ;;
        --repo) REPO_URL="$2"; shift 2 ;;
        --arch) ARCH="$2"; shift 2 ;;
        --dry-run) DRY_RUN=true; shift ;;
        *) error "Unknown option: $1"; exit 1 ;;
    esac
done

[[ -z "$ROOT" || ! -d "$ROOT" ]] && { error "Invalid root directory: $ROOT"; exit 1; }

if $DRY_RUN; then
    log "Would install base system into $ROOT using repository $REPO_URL"
    exit 0
fi

log "Installing base system into $ROOT"
xbps-install -S -R "$REPO_URL" -r "$ROOT" -y base-system

log "Base system installation completed"
exit 0
