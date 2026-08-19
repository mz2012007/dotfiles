#!/usr/bin/env bash
set -Eeuo pipefail

log() { printf '[INFO] %s\n' "$*"; }
error() { printf '[ERROR] %s\n' "$*" >&2; }

ROOT=""
HOSTNAME="myiso"
DRY_RUN=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --root) ROOT="$2"; shift 2 ;;
        --hostname) HOSTNAME="$2"; shift 2 ;;
        --dry-run) DRY_RUN=true; shift ;;
        *) error "Unknown option: $1"; exit 1 ;;
    esac
done

[[ -z "$ROOT" || ! -d "$ROOT" ]] && { error "Invalid root directory: $ROOT"; exit 1; }

if $DRY_RUN; then
    log "Would set hostname to $HOSTNAME and enable dhcpcd"
    exit 0
fi

log "Configuring network"
echo "$HOSTNAME" > "$ROOT/etc/hostname"

# Create /etc/hosts
cat > "$ROOT/etc/hosts" <<EOF
127.0.0.1   localhost
::1         localhost
127.0.1.1   $HOSTNAME.localdomain $HOSTNAME
EOF

# Enable dhcpcd service (runit)
chroot "$ROOT" ln -s /etc/sv/dhcpcd /var/service/ 2>/dev/null || true

log "Network configuration completed"
exit 0
