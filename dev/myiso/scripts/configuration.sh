#!/usr/bin/env bash
set -Eeuo pipefail

log() { printf '[INFO] %s\n' "$*"; }
error() { printf '[ERROR] %s\n' "$*" >&2; }

ROOT=""
HOSTNAME="myiso"
TIMEZONE="UTC"
LOCALE="en_US.UTF-8"
KEYBOARD="us"
DRY_RUN=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --root) ROOT="$2"; shift 2 ;;
        --hostname) HOSTNAME="$2"; shift 2 ;;
        --timezone) TIMEZONE="$2"; shift 2 ;;
        --locale) LOCALE="$2"; shift 2 ;;
        --keyboard) KEYBOARD="$2"; shift 2 ;;
        --dry-run) DRY_RUN=true; shift ;;
        *) error "Unknown option: $1"; exit 1 ;;
    esac
done

[[ -z "$ROOT" || ! -d "$ROOT" ]] && { error "Invalid root directory: $ROOT"; exit 1; }

if $DRY_RUN; then
    log "Would configure timezone=$TIMEZONE, locale=$LOCALE, keyboard=$KEYBOARD"
    exit 0
fi

log "Configuring system"

# Timezone
chroot "$ROOT" ln -sf "/usr/share/zoneinfo/$TIMEZONE" /etc/localtime

# Locale
echo "$LOCALE" > "$ROOT/etc/locale.conf"
echo "LANG=$LOCALE" > "$ROOT/etc/locale.conf"

# Keyboard layout (for console)
echo "KEYMAP=$KEYBOARD" > "$ROOT/etc/vconsole.conf"

# Generate fstab (simple, using UUIDs)
ROOT_UUID=$(blkid -s UUID -o value "$(findmnt -n -o SOURCE --target "$ROOT")")
EFI_UUID=$(blkid -s UUID -o value "$(findmnt -n -o SOURCE --target "$ROOT/boot/efi")")

cat > "$ROOT/etc/fstab" <<EOF
UUID=$ROOT_UUID / ext4 defaults 0 1
UUID=$EFI_UUID /boot/efi vfat defaults 0 2
EOF

log "System configuration completed"
exit 0
