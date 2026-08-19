#!/usr/bin/env bash
set -Eeuo pipefail

log() { printf '[INFO] %s\n' "$*"; }
error() { printf '[ERROR] %s\n' "$*" >&2; }

DISK=""
ROOT=""
DRY_RUN=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --disk) DISK="$2"; shift 2 ;;
        --root) ROOT="$2"; shift 2 ;;
        --dry-run) DRY_RUN=true; shift ;;
        *) error "Unknown option: $1"; exit 1 ;;
    esac
done

[[ -z "$DISK" ]] && { error "Disk must be specified"; exit 1; }
[[ -z "$ROOT" ]] && { error "Root mount point must be specified"; exit 1; }

if $DRY_RUN; then
    log "Would mount root partition to $ROOT"
    log "Would mount EFI partition to $ROOT/boot/efi"
    exit 0
fi

# Determine partition suffixes
if [[ "$DISK" == *"nvme"* ]]; then
    EFI_PART="${DISK}p1"
    ROOT_PART="${DISK}p2"
else
    EFI_PART="${DISK}1"
    ROOT_PART="${DISK}2"
fi

mkdir -p "$ROOT"
log "Mounting root partition $ROOT_PART to $ROOT"
mount "$ROOT_PART" "$ROOT"

mkdir -p "$ROOT/boot/efi"
log "Mounting EFI partition $EFI_PART to $ROOT/boot/efi"
mount "$EFI_PART" "$ROOT/boot/efi"

log "Mounting completed"
exit 0
