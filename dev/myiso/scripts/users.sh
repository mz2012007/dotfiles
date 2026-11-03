#!/usr/bin/env bash
set -Eeuo pipefail

log() { printf '[INFO] %s\n' "$*"; }
error() { printf '[ERROR] %s\n' "$*" >&2; }

ROOT=""
USERNAME=""
PASSWORD=""  # optional; if empty, account is locked
DRY_RUN=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --root) ROOT="$2"; shift 2 ;;
        --username) USERNAME="$2"; shift 2 ;;
        --password) PASSWORD="$2"; shift 2 ;;
        --dry-run) DRY_RUN=true; shift ;;
        *) error "Unknown option: $1"; exit 1 ;;
    esac
done

[[ -z "$ROOT" || ! -d "$ROOT" ]] && { error "Invalid root directory: $ROOT"; exit 1; }
[[ -z "$USERNAME" ]] && { error "Username must be specified"; exit 1; }

if $DRY_RUN; then
    log "Would create user $USERNAME in $ROOT"
    exit 0
fi

log "Creating user $USERNAME"
chroot "$ROOT" useradd -m -G wheel,audio,video,cdrom,input "$USERNAME"

if [[ -n "$PASSWORD" ]]; then
    log "Setting password for $USERNAME"
    echo "$USERNAME:$PASSWORD" | chpasswd -R "$ROOT"
fi

log "User creation completed"
exit 0
