# modules/system.sh - Full system update and cleanup for Void Linux

# Known problematic packages that may break -Su due to shlib mismatches
# (aquamarine from hyprland-void needs libdisplay-info.so.2 but system has .so.3)
_ensure_ignore_aquamarine() {
  local ignore_conf="/etc/xbps.d/99-ignore-aquamarine.conf"

  # Only act if aquamarine is installed via xbps
  if ! xbps-query -l aquamarine >/dev/null 2>&1; then
    return 0
  fi

  if [[ ! -f "$ignore_conf" ]]; then
    warn "Adding aquamarine to xbps ignore list (known shlib conflict)"
    echo "ignorepkg=aquamarine" | sudo tee "$ignore_conf" >/dev/null
  fi

  # Hold it so it doesn't get updated or downgraded
  if ! xbps-pkgdb -m listhold 2>/dev/null | grep -q '^aquamarine$'; then
    sudo xbps-pkgdb -m hold aquamarine 2>/dev/null || true
  fi
}

module_system_update() {
  step "System (xbps full upgrade)"

  # --- 0. Known fixes ---
  _ensure_ignore_aquamarine

  # --- 1. Update xbps itself first ---
  echo "  Updating xbps..."
  if ! sudo xbps-install -Suy xbps; then
    fail "Failed to update xbps"
    return 1
  fi
  ok "xbps is up to date"

  # --- 2. Sync all repos ---
  echo "  Syncing repositories..."
  if ! sudo xbps-install -S; then
    fail "Failed to sync repositories"
    return 1
  fi

  # --- 3. Full system upgrade ---
  local pending
  pending=$(sudo xbps-install -Sun 2>/dev/null || true)

  if [[ -z "$pending" ]]; then
    ok "System is already up to date"
  else
    echo "  Pending changes:"
    printf '%s\n' "$pending" | sed 's/^/    /'
    echo ""
    if ! sudo xbps-install -Suy; then
      fail "System upgrade failed"
      return 1
    fi
    ok "System upgraded"
  fi

  # --- 4. Remove orphaned packages ---
  local orphans
  orphans=$(sudo xbps-remove -on 2>/dev/null || true)

  if [[ -z "$orphans" ]]; then
    echo "  No orphaned packages"
  else
    echo "  Removing orphans:"
    printf '%s\n' "$orphans" | sed 's/^/    /'
    if sudo xbps-remove -oy; then
      ok "Orphaned packages removed"
    else
      warn "Failed to remove some orphans"
    fi
  fi

  # --- 5. Clean package cache ---
  if command -v vkpurge >/dev/null 2>&1; then
    echo "  Purging old package versions from cache..."
    sudo vkpurge rm all 2>/dev/null || true
    ok "Package cache cleaned"
  fi

  ok "System maintenance complete"
}
