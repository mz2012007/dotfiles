#!/usr/bin/env bash
set -Eeuo pipefail

log() { printf '[INFO] %s\n' "$*"; }
error() { printf '[ERROR] %s\n' "$*" >&2; }

# Check root
if [[ $EUID -ne 0 ]]; then
    error "Must run as root"
    exit 1
fi

# Required commands
required_cmds=(parted mkfs.ext4 mkfs.fat mount xbps-install xbps-reconfigure chroot grub-install)
for cmd in "${required_cmds[@]}"; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        error "Missing command: $cmd"
        exit 1
    fi
done

# Memory check (2 GB)
mem_kb=$(awk '/MemTotal/{print $2}' /proc/meminfo)
if [[ $mem_kb -lt 2000000 ]]; then
    error "Not enough RAM (less than 2GB)"
    exit 1
fi

# Target disk check if provided
if [[ -n "${TARGET_DISK:-}" ]]; then
    if [[ ! -b "$TARGET_DISK" ]]; then
        error "Target disk does not exist or is not a block device: $TARGET_DISK"
        exit 1
    fi
fi

log "Preflight checks passed"
exit 0
