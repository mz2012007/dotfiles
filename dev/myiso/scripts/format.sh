#!/usr/bin/env bash
set -Eeuo pipefail

log() { printf '[INFO] %s\n' "$*"; }
error() { printf '[ERROR] %s\n' "$*" >&2; }

DISK=""
FILESYSTEM="ext4"
DRY_RUN=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --disk) DISK="$2"; shift 2 ;;
        --filesystem) FILESYSTEM="$2"; shift 2 ;;
        --dry-run) DRY_RUN=true; shift ;;
        *) error "Unknown option: $1"; exit 1 ;;
    esac
done

[[ -z "$DISK" ]] && { error "Disk must be specified"; exit 1; }
[[ ! -b "$DISK" ]] && { error "Invalid disk: $DISK"; exit 1; }

# Validate filesystem
case "$FILESYSTEM" in
    ext4) MKFS_CMD="mkfs.ext4" ;;
    xfs) MKFS_CMD="mkfs.xfs" ;;
    btrfs) MKFS_CMD="mkfs.btrfs" ;;
    *) error "Unsupported filesystem: $FILESYSTEM"; exit 1 ;;
esac

if $DRY_RUN; then
    log "Would format EFI partition ${DISK}1 as FAT32"
    log "Would format root partition ${DISK}2 as $FILESYSTEM"
    exit 0
fi

# Determine partition suffixes (handle NVMe)
if [[ "$DISK" == *"nvme"* ]]; then
    EFI_PART="${DISK}p1"
    ROOT_PART="${DISK}p2"
else
    EFI_PART="${DISK}1"
    ROOT_PART="${DISK}2"
fi

log "Formatting EFI partition $EFI_PART"
mkfs.fat -F32 "$EFI_PART"

log "Formatting root partition $ROOT_PART as $FILESYSTEM"
$MKFS_CMD -L "myiso-root" "$ROOT_PART"

log "Formatting completed"
exit 0
