# modules/dms.sh - DankMaterialShell (DMS) updater
# DMS is distributed via the official XBPS repos at void.danklinux.com.

DMS_REPO_DANK="/etc/xbps.d/50-danklinux.conf"
DMS_REPO_DMS="/etc/xbps.d/50-dms.conf"
DMS_REPO_DANK_URL="https://void.danklinux.com/danklinux/current"
DMS_REPO_DMS_URL="https://void.danklinux.com/dms/current"
DMS_BIN="/usr/bin/dms"

# --- Version detection: try multiple flags, capture stderr too ---
_dms_version_installed() {
  if [[ ! -x "$DMS_BIN" ]]; then
    echo "none"
    return
  fi
  local out ver flag
  for flag in "--version" "-v" "version"; do
    out=$("$DMS_BIN" "$flag" 2>&1 || true)
    ver=$(printf '%s\n' "$out" | grep -oP '\d+\.\d+\.\d+' | head -1 || true)
    if [[ -n "$ver" ]]; then
      echo "$ver"
      return
    fi
  done
  echo "unknown"
}

# --- Find the xbps package that owns /usr/bin/dms ---
_dms_owner_pkg() {
  [[ -x "$DMS_BIN" ]] || return 0
  local raw
  raw=$(xbps-query -o "$DMS_BIN" 2>/dev/null | head -1)
  [[ -z "$raw" ]] && return 0
  # Format: "pkgname-version_rev: /path/file (type)"
  printf '%s\n' "$raw" |
    awk -F: '{print $1}' |
    sed -E 's/-[0-9][^-]*$//'
}

# --- Ensure the repos are configured with the right content ---
_ensure_dms_repos() {
  local want_dank="repository=${DMS_REPO_DANK_URL}"
  local want_dms="repository=${DMS_REPO_DMS_URL}"

  if [[ ! -f "$DMS_REPO_DANK" ]] || ! grep -qxF "$want_dank" "$DMS_REPO_DANK" 2>/dev/null; then
    echo "  Adding repo: danklinux"
    printf '%s\n' "$want_dank" | sudo tee "$DMS_REPO_DANK" >/dev/null
  fi

  if [[ ! -f "$DMS_REPO_DMS" ]] || ! grep -qxF "$want_dms" "$DMS_REPO_DMS" 2>/dev/null; then
    echo "  Adding repo: dms"
    printf '%s\n' "$want_dms" | sudo tee "$DMS_REPO_DMS" >/dev/null
  fi

  echo "  Syncing repositories..."
  if ! sudo xbps-install -S; then
    fail "Failed to sync repositories"
    return 1
  fi

  # Simple, robust check: can xbps find 'dms' in any repo?
  if ! xbps-query -R dms >/dev/null 2>&1; then
    fail "Package 'dms' not found in repository pool after sync"
    return 1
  fi

  ok "DMS repositories configured"
}

module_dms_update() {
  step "DankMaterialShell (DMS)"

  local cur pkg new
  cur=$(_dms_version_installed)
  echo "  Installed version: $cur"

  _ensure_dms_repos || return 1

  pkg=$(_dms_owner_pkg)
  if [[ -z "$pkg" ]]; then
    warn "DMS is not installed via xbps."
    read -rp "  Install DMS now? [y/N] " ans
    [[ "$ans" =~ ^[Yy]$ ]] || {
      echo "  Skipped."
      return 0
    }
    pkg="dms"
  fi
  echo "  xbps package:      $pkg"

  echo "  Updating via xbps..."
  if sudo xbps-install -Syu "$pkg"; then
    new=$(_dms_version_installed)
    if [[ "$cur" == "$new" ]]; then
      ok "DMS is already up to date ($cur)"
    else
      ok "DMS updated: $cur → $new"
      if pgrep -x dms >/dev/null 2>&1; then
        echo "  Restarting DMS..."
        dms restart >/dev/null 2>&1 || warn "Could not restart DMS"
      fi
    fi
  else
    fail "DMS update failed"
    return 1
  fi
}
