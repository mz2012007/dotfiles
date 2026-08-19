#!/usr/bin/env bash
set -Eeuo pipefail

log() { printf '[INFO] %s\n' "$*"; }
error() { printf '[ERROR] %s\n' "$*" >&2; }

ROOT=""
KERNEL_PKG="linux"
DRY_RUN=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --root) ROOT="$2"; shift 2 ;;
        --kernel) KERNEL_PKG="$2"; shift 2 ;;
        --dry-run) DRY_RUN=true; shift ;;
        *) error "Unknown option: $1"; exit 1 ;;
    esac
done

[[ -z "$ROOT" || ! -d "$ROOT" ]] && { error "Invalid root directory: $ROOT"; exit 1; }

if $DRY_RUN; then
    log "Would install kernel package: $KERNEL_PKG"
    exit 0
fi

log "Installing kernel: $KERNEL_PKG"
xbps-install -S -r "$ROOT" -y "$KERNEL_PKG"

log "Reconfiguring kernel modules"
chroot "$ROOT" xbps-reconfigure -f "$KERNEL_PKG"

log "Kernel setup completed"
exit 0
