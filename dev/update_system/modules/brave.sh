# modules/brave.sh - Brave Browser updater
# Installs latest stable Brave from official GitHub .deb releases.

BRAVE_DIR="/opt/brave.com/brave"
BRAVE_BIN="$BRAVE_DIR/brave-browser"
BRAVE_CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/update-system/brave"
BRAVE_API="https://api.github.com/repos/brave/brave-browser/releases/latest"
BRAVE_DEB_BASE="https://github.com/brave/brave-browser/releases/download"

_brave_version_installed() {
  [[ -x "$BRAVE_BIN" ]] || {
    echo "none"
    return
  }

  local out ver
  out=$("$BRAVE_BIN" --version 2>&1 || true)

  # Brave may print:
  #   "Brave Browser 1.97.59 Chromium: 155.0.7342.98"
  #   "Brave Browser 155.1.97.59"
  ver=$(printf '%s\n' "$out" |
    sed -nE 's/.*Brave Browser[[:space:]]+([0-9][0-9.]*).*/\1/p' |
    head -1)

  [[ -z "$ver" ]] && {
    echo "unknown"
    return
  }

  # Keep the last three dot-separated components.
  printf '%s\n' "$ver" |
    awk -F. '{n=NF; if(n>=3) print $(n-2)"."$(n-1)"."$n; else print $0}'
}

_brave_version_latest() {
  curl -fsSL --max-time 20 "$BRAVE_API" 2>/dev/null |
    grep -oP '"tag_name":\s*"v\K[^"]+' |
    head -1 ||
    true
}

_brave_fetch_checksum() {
  local version="$1"
  curl -fsSL --max-time 20 \
    "${BRAVE_DEB_BASE}/v${version}/brave-browser_${version}_amd64.deb.sha256" \
    2>/dev/null |
    awk 'NF{print $1; exit}' ||
    true
}

module_brave_update() {
  step "Brave Browser"

  local cur new deb_url deb_file expected_sha
  cur=$(_brave_version_installed)
  echo "  Installed version: $cur"

  echo "  Checking latest release..."
  new=$(_brave_version_latest)
  if [[ -z "${new:-}" ]]; then
    fail "Could not fetch latest version from GitHub"
    return 1
  fi
  echo "  Latest version:    $new"

  if [[ "$cur" == "$new" ]]; then
    ok "Brave is already up to date ($cur)"
    return 0
  fi

  # Warn if managed by xbps
  if xbps-query brave-browser-bin >/dev/null 2>&1 ||
    xbps-query brave-bin >/dev/null 2>&1; then
    warn "Brave is installed via xbps. This update will bypass xbps."
    read -rp "  Continue anyway? [y/N] " ans
    [[ "$ans" =~ ^[Yy]$ ]] || return 0
  fi

  mkdir -p "$BRAVE_CACHE"
  deb_url="${BRAVE_DEB_BASE}/v${new}/brave-browser_${new}_amd64.deb"
  deb_file="$BRAVE_CACHE/brave-browser_${new}_amd64.deb"

  expected_sha=$(_brave_fetch_checksum "$new")
  if [[ -n "$expected_sha" ]]; then
    echo "  Expected SHA256: $expected_sha"
  else
    warn "Could not fetch official SHA256 checksum"
  fi

  # Verify cached file if present
  if [[ -f "$deb_file" && -s "$deb_file" ]]; then
    if [[ -n "$expected_sha" ]]; then
      if verify_sha256 "$deb_file" "$expected_sha"; then
        echo "  Cached file verified: $deb_file"
      else
        warn "Cached file corrupted, removing"
        rm -f "$deb_file"
      fi
    else
      echo "  Using cached (unverified): $deb_file"
    fi
  fi

  # Download if needed
  if [[ ! -f "$deb_file" || ! -s "$deb_file" ]]; then
    echo "  Downloading: $deb_url"
    if ! curl -fL --progress-bar --max-time 600 \
      -o "$deb_file.part" "$deb_url"; then
      rm -f "$deb_file.part"
      fail "Download failed"
      return 1
    fi

    if [[ -n "$expected_sha" ]]; then
      if ! verify_sha256 "$deb_file.part" "$expected_sha"; then
        rm -f "$deb_file.part"
        fail "Checksum mismatch on downloaded file"
        return 1
      fi
      ok "Download checksum verified"
    else
      warn "Skipping checksum verification (no official hash)"
    fi

    mv "$deb_file.part" "$deb_file"
  fi

  # Extract + install in a subshell so the EXIT trap
  # is scoped and cannot leak into other functions.
  if ! (
    set -e
    tmp=$(mktemp -d)
    trap 'rm -rf "$tmp"' EXIT

    echo "  Extracting .deb..."
    cp "$deb_file" "$tmp/brave.deb"
    (cd "$tmp" && ar x brave.deb)

    data_tar=$(find "$tmp" -maxdepth 1 -name 'data.tar.*' | head -1)
    [[ -n "$data_tar" ]] || {
      echo "data.tar.* missing" >&2
      exit 2
    }
    tar -xf "$data_tar" -C "$tmp"

    [[ -d "$tmp/opt/brave.com/brave" ]] || {
      echo "Unexpected .deb layout" >&2
      exit 3
    }

    echo "  Installing to $BRAVE_DIR"
    sudo mkdir -p "$BRAVE_DIR"
    sudo cp -a "$tmp/opt/brave.com/brave/." "$BRAVE_DIR/"

    echo "  Updating symlinks"
    sudo ln -sf "$BRAVE_BIN" /usr/bin/brave-browser
    sudo ln -sf "$BRAVE_BIN" /usr/bin/brave

    if [[ -d "$tmp/usr/share/applications" ]]; then
      sudo mkdir -p /usr/share/applications
      sudo cp -a "$tmp/usr/share/applications/"*.desktop \
        /usr/share/applications/ 2>/dev/null || true
    fi

    if [[ -d "$tmp/usr/share/icons" ]]; then
      sudo cp -a "$tmp/usr/share/icons/." /usr/share/icons/ \
        2>/dev/null || true
    fi

    if command -v update-desktop-database >/dev/null 2>&1; then
      sudo update-desktop-database /usr/share/applications \
        2>/dev/null || true
    fi
  ); then
    fail "Extraction/install failed"
    return 1
  fi

  ok "Brave updated: $cur → $new"
}
