#!/usr/bin/env bash
set -Eeuo pipefail

log() { printf '[INFO] %s\n' "$*"; }
error() { printf '[ERROR] %s\n' "$*" >&2; }

ROOT=""
DISK=""
BOOTLOADER="grub"
EFI_DIR="/boot/efi"
DRY_RUN=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --root) ROOT="$2"; shift 2 ;;
        --disk) DISK="$2"; shift 2 ;;
        --bootloader) BOOTLOADER="$2"; shift 2 ;;
        --efi-dir) EFI_DIR="$2"; shift 2 ;;
        --dry-run) DRY_RUN=true; shift ;;
        *) error "Unknown option: $1"; exit 1 ;;
    esac
done

[[ -z "$ROOT" || ! -d "$ROOT" ]] && { error "Invalid root directory: $ROOT"; exit 1; }
[[ -z "$DISK" ]] && { error "Disk must be specified"; exit 1; }

if $DRY_RUN; then
    log "Would install $BOOTLOADER to $DISK"
    exit 0
fi

case "$BOOTLOADER" in
    grub)
        log "Installing GRUB"
        xbps-install -S -r "$ROOT" -y grub

        # Detect EFI vs BIOS
        if [[ -d "$ROOT/sys/firmware/efi" ]]; then
            log "EFI system detected"
            xbps-install -S -r "$ROOT" -y grub-x86_64-efi
            chroot "$ROOT" grub-install --target=x86_64-efi --efi-directory="$EFI_DIR" --bootloader-id=void
        else
            log "BIOS system detected"
            chroot "$ROOT" grub-install "$DISK"
        fi

        chroot "$ROOT" grub-mkconfig -o /boot/grub/grub.cfg
        ;;
    syslinux)
        log "Installing syslinux"
        xbps-install -S -r "$ROOT" -y syslinux
        chroot "$ROOT" syslinux-install_update -i -a -m
        ;;
    *)
        error "Unsupported bootloader: $BOOTLOADER"
        exit 1
        ;;
esac

log "Bootloader installation completed"
exit 0
