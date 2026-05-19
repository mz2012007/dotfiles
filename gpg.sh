#!/usr/bin/env bash

# SSH key bootstrap script
# - Decrypts id_ed25519.gpg if present
# - Leaves plaintext key untouched if already available
# - Ensures correct permissions
# - Regenerates public key if missing

set -euo pipefail

DOTFILES="$HOME/dotfiles/my-config/myroot/myhome/.ssh"
SSH_DIR="$HOME/.ssh"
KEY="$SSH_DIR/id_ed25519"
GPG_FILE="$DOTFILES/id_ed25519.gpg"
KEY_GPG="$KEY.gpg"
PUB_KEY="$KEY.pub"

# --------------------------
# Color support (TTY-aware)
# --------------------------
if [[ -t 1 ]]; then
  RED="\033[31m"
  GREEN="\033[32m"
  YELLOW="\033[33m"
  BLUE="\033[34m"
  RESET="\033[0m"
else
  RED="" GREEN="" YELLOW="" BLUE="" RESET=""
fi

info() { echo -e "${BLUE}ℹ️  $*${RESET}"; }
warn() { echo -e "${YELLOW}⚠️  $*${RESET}"; }
success() { echo -e "${GREEN}✅ $*${RESET}"; }
error() {
  echo -e "${RED}❌ $*${RESET}"
  exit 1
}

# --------------------------------------------------------

mkdir -p "$SSH_DIR"
chmod 700 "$SSH_DIR"

if [[ -f "$GPG_FILE" ]]; then
  info "cp gpg -> $SSH_DIR"
  cp $GPG_FILE $SSH_DIR || error "While copy gpg"
  success "copied gpg "
fi

if [[ -f "$KEY" ]]; then
  info "[+] SSH private key already exists. Nothing to do."

elif [[ -f "$KEY_GPG" ]]; then
  info "[*] Encrypted SSH key found. Decrypting..."
  gpg -d "$KEY_GPG" >"$KEY"
  chmod 600 "$KEY"
  success "[+] SSH key decrypted successfully."

else
  error "[-] No SSH key found (neither plaintext nor encrypted)."
  exit 1
fi

if [[ ! -f "$PUB_KEY" ]]; then
  info "[*] Public key missing. Regenerating..."
  ssh-keygen -y -f "$KEY" >"$PUB_KEY"
  chmod 644 "$PUB_KEY"
  success "[+] Public key generated."
fi

echo "[✓] SSH key setup complete."
info "Cleaning"
rm $SSH_DIR/id_ed25519.gpg || error "remove $SSH_DIR/id_ed25519.gpg"
success "Cleaning"
