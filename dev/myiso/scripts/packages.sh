#!/usr/bin/env bash
set -Eeuo pipefail

log() { printf '[INFO] %s\n' "$*"; }
error() { printf '[ERROR] %s\n' "$*" >&2; }

ROOT=""
PROFILE="minimal"
REPO_URL="https://repo-default.voidlinux.org/current"
DRY_RUN=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --root) ROOT="$2"; shift 2 ;;
        --profile) PROFILE="$2"; shift 2 ;;
        --repo) REPO_URL="$2"; shift 2 ;;
        --dry-run) DRY_RUN=true; shift ;;
        *) error "Unknown option: $1"; exit 1 ;;
    esac
done

[[ -z "$ROOT" || ! -d "$ROOT" ]] && { error "Invalid root directory: $ROOT"; exit 1; }

case "$PROFILE" in
    minimal)
        PKGS="base-system linux"
        ;;
    server)
        PKGS="base-system linux openssh dhcpcd"
        ;;
    desktop)
        PKGS="base-system linux NetworkManager xorg plasma-desktop"
        ;;
    development)
        PKGS="base-system linux git vim gcc make"
        ;;
    custom)
        if [[ -f config/packages.conf ]]; then
            PKGS=$(grep -v '^#' config/packages.conf | tr '\n' ' ')
        else
            error "config/packages.conf not found for custom profile"
            exit 1
        fi
        ;;
    *)
        error "Unknown profile: $PROFILE"
        exit 1
        ;;
esac

if $DRY_RUN; then
    log "Would install packages: $PKGS"
    exit 0
fi

log "Installing packages: $PKGS"
xbps-install -S -R "$REPO_URL" -r "$ROOT" -y $PKGS

log "Package installation completed"
exit 0
