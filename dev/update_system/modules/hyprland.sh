# modules/hyprland.sh - Hyprland updater for Void Linux
# Hyprland is not in the official Void repository. It is provided by the
# hyprland-void project, which we install via its binary repository.
# If the update fails due to aquamarine/libdisplay-info shlib mismatch,
# we print guidance on how to fix it by building from source.

HYPR_REPO_CONF="/etc/xbps.d/hyprland-void-repo.conf"
HYPR_REPO_URL="https://github.com/void-land/hyprland-void-packages/releases/latest/download/"
HYPR_BIN="/usr/bin/Hyprland"

_hypr_version_installed() {
  if [[ -x "$HYPR_BIN" ]]; then
    "$HYPR_BIN" --version 2>/dev/null | grep -oP '\d+\.\d+\.\d+' | head -1 || echo "unknown"
  else
    echo "none"
  fi
}

_hypr_repo_present() {
  # Check if the repo file exists AND contains the expected URL
  [[ -f "$HYPR_REPO_CONF" ]] && grep -qxF "repository=${HYPR_REPO_URL}" "$HYPR_REPO_CONF" 2>/dev/null
}

_ensure_hypr_repo() {
  if ! _hypr_repo_present; then
    step "Adding Hyprland repository"
    echo "repository=${HYPR_REPO_URL}" | sudo tee "$HYPR_REPO_CONF" >/dev/null
    echo "  Syncing repositories..."
    if ! sudo xbps-install -S; then
      fail "Failed to sync repositories"
      return 1
    fi
    ok "Hyprland repository configured"
  fi

  # Verify that xbps can find the 'hyprland' package
  if ! xbps-query -R hyprland >/dev/null 2>&1; then
    fail "Package 'hyprland' not found in repository pool after sync"
    return 1
  fi
}

module_hyprland_update() {
  step "Hyprland"

  local cur new
  cur=$(_hypr_version_installed)
  echo "  Installed version: $cur"

  _ensure_hypr_repo || return 1

  echo "  Updating via xbps..."
  # Run the update. We capture output to detect the known shlib error.
  local out
  if out=$(sudo xbps-install -Syu hyprland 2>&1); then
    echo "$out"
    new=$(_hypr_version_installed)
    if [[ "$cur" == "$new" ]]; then
      ok "Hyprland is already up to date ($cur)"
    else
      ok "Hyprland updated: $cur → $new"
    fi
  else
    echo "$out" >&2
    if grep -q "broken, unresolvable shlib" <<<"$out"; then
      warn "Update failed due to a shared library mismatch (aquamarine/libdisplay-info)."
      warn "This is a known issue with the binary repository."
      warn "To fix it, build aquamarine and hyprland from source using void-packages:"
      warn "  1. cd ~/void-packages"
      warn "  2. XBPS_SKIP_DEPS=1 ./xbps-src pkg aquamarine"
      warn "  3. sudo xbps-install -R hostdir/binpkgs aquamarine"
      warn "  4. XBPS_SKIP_DEPS=1 ./xbps-src pkg hyprland"
      warn "  5. sudo xbps-install -R hostdir/binpkgs hyprland"
      warn "Then re-run this module."
    fi
    fail "Hyprland update failed"
    return 1
  fi
}
