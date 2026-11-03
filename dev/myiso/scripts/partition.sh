#!/usr/bin/env bash
set -Eeuo pipefail

log() { printf '[INFO] %s\n' "$*"; }
error() { printf '[ERROR] %s\n' "$*" >&2; }

DRY_RUN=false
DISK=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run) DRY_RUN=true; shift ;;
        --disk) DISK="$2"; shift 2 ;;
        *) error "Unknown option: $1"; exit 1 ;;
    esac
done

[[ -z "$DISK" ]] && { error "Disk must be specified"; exit 1; }
[[ ! -b "$DISK" ]] && { error "Invalid disk: $DISK"; exit 1; }

if $DRY_RUN; then
    log "Would partition $DISK with GPT layout:"
    log "  - EFI System Partition: 512MB (FAT32)"
    log "  - Root partition: remaining space (ext4)"
    exit 0
fi

log "Partitioning $DISK with GPT"
parted -s "$DISK" mklabel gpt
parted -s "$DISK" mkpart primary fat32 1MiB 513MiB
parted -s "$DISK" set 1 esp on
parted -s "$DISK" mkpart primary ext4 513MiB 100%

log "Partitioning completed"
exit 0
