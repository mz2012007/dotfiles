# lib/common.sh - Shared helpers for update-system
# Sourced by the main script; do not execute directly.

# ============ Colors ============
R='\033[0;31m'
G='\033[0;32m'
Y='\033[1;33m'
B='\033[0;34m'
N='\033[0m'
step() { echo -e "\n${B}==>${N} ${B}$*${N}"; }
ok() { echo -e "${G}[✓]${N} $*"; }
warn() { echo -e "${Y}[!]${N} $*"; }
fail() { echo -e "${R}[✗]${N} $*" >&2; }

# ============ Sudo Keepalive ============
KEEP_SUDO_PID=""

start_sudo_keepalive() {
  [[ -n "$KEEP_SUDO_PID" ]] && return 0 # idempotent
  if ! sudo -v; then
    fail "sudo authentication failed"
    exit 1
  fi
  (while true; do
    sudo -n true 2>/dev/null
    sleep 50
  done) &
  KEEP_SUDO_PID=$!
  trap 'kill $KEEP_SUDO_PID 2>/dev/null || true' EXIT
}

# Generic SHA256 verifier — used by all modules
verify_sha256() {
  local file="$1" expected="$2"
  [[ -z "$expected" ]] && return 2
  local actual
  actual=$(sha256sum "$file" | awk '{print $1}')
  if [[ "$actual" != "$expected" ]]; then
    echo "    expected: $expected" >&2
    echo "    actual:   $actual" >&2
    return 1
  fi
  return 0
}
