#!/usr/bin/env bash
# modules/opencode-desktop.sh - OpenCode Desktop updater for Void Linux.
# Uses the official stable x64 DEB URL and extracts it without invoking dpkg.

OPENCODE_DESKTOP_URL="https://opencode.ai/download/stable/linux-x64-deb"
OPENCODE_DESKTOP_DIR="/opt/OpenCode"
OPENCODE_DESKTOP_CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/update-system/opencode-desktop"
OPENCODE_DESKTOP_VERSION_FILE="$OPENCODE_DESKTOP_DIR/.update-system-version"
OPENCODE_DESKTOP_FINGERPRINT_FILE="$OPENCODE_DESKTOP_DIR/.update-system-fingerprint"

_opencode_desktop_remote_fingerprint() {
  local headers etag modified length
  headers=$(mktemp) || return 1

  if ! curl -fsSLI --retry 1 --max-time 45 \
    -D "$headers" -o /dev/null "$OPENCODE_DESKTOP_URL"; then
    rm -f "$headers"
    return 1
  fi

  etag=$(grep -i '^etag:' "$headers" | tail -n 1 | sed -E 's/^[^:]*:[[:space:]]*//; s/\r$//')
  modified=$(grep -i '^last-modified:' "$headers" | tail -n 1 | sed -E 's/^[^:]*:[[:space:]]*//; s/\r$//')
  length=$(grep -i '^content-length:' "$headers" | tail -n 1 | sed -E 's/^[^:]*:[[:space:]]*//; s/\r$//')
  rm -f "$headers"

  # Content length alone is not a safe update fingerprint; require a server-side
  # validator or modification time as well.
  [[ -n "$etag$modified" ]] || return 1
  printf 'etag=%s\nlast-modified=%s\ncontent-length=%s\n' "$etag" "$modified" "$length"
}

_opencode_desktop_installed_version() {
  if [[ -r "$OPENCODE_DESKTOP_VERSION_FILE" ]]; then
    cat "$OPENCODE_DESKTOP_VERSION_FILE"
  elif [[ -x "$OPENCODE_DESKTOP_DIR/ai.opencode.desktop" ]]; then
    printf '%s\n' "unknown"
  else
    printf '%s\n' "none"
  fi
}

module_opencode-desktop_update() {
  step "OpenCode Desktop"

  local current remote_fingerprint installed_fingerprint deb_file tmp
  local data_archive control_archive control_file package_version
  local app_source app_binary app_stage app_backup item
  local cache_fingerprint_file

  case "$(uname -m)" in
  x86_64 | amd64) ;;
  *)
    fail "The official package URL is for Linux x64; unsupported architecture: $(uname -m)"
    return 1
    ;;
  esac

  for cmd in curl ar tar awk grep sed find; do
    command -v "$cmd" >/dev/null 2>&1 || {
      fail "Required command not found: $cmd"
      return 1
    }
  done

  current=$(_opencode_desktop_installed_version)
  echo "  Installed version: $current"

  # The stable endpoint may not provide a human-readable version in its URL.
  # Use response metadata to avoid downloading the large package on every run.
  remote_fingerprint=$(_opencode_desktop_remote_fingerprint 2>/dev/null || true)
  installed_fingerprint=""
  if [[ -r "$OPENCODE_DESKTOP_FINGERPRINT_FILE" ]]; then
    installed_fingerprint=$(cat "$OPENCODE_DESKTOP_FINGERPRINT_FILE")
  fi

  if [[ -n "$remote_fingerprint" && "$remote_fingerprint" == "$installed_fingerprint" &&
    "$current" != "none" && "$current" != "unknown" ]]; then
    ok "OpenCode Desktop is up to date ($current)"
    return 0
  fi
  if [[ -z "$remote_fingerprint" ]]; then
    warn "The server did not provide usable update metadata; the package will be checked directly"
  fi

  mkdir -p "$OPENCODE_DESKTOP_CACHE"
  deb_file="$OPENCODE_DESKTOP_CACHE/opencode-desktop-stable.deb"
  cache_fingerprint_file="$deb_file.fingerprint"

  if [[ -n "$remote_fingerprint" && -s "$deb_file" && -r "$cache_fingerprint_file" &&
    "$(cat "$cache_fingerprint_file")" == "$remote_fingerprint" ]]; then
    echo "  Using cached package for the current stable build"
  else
    rm -f "$deb_file" "$cache_fingerprint_file" "$deb_file.part"
    echo "  Downloading the official stable DEB..."
    if ! curl -fL --retry 2 --connect-timeout 20 --max-time 900 \
      --progress-bar -o "$deb_file.part" "$OPENCODE_DESKTOP_URL"; then
      rm -f "$deb_file.part"
      fail "OpenCode Desktop download failed"
      return 1
    fi
    if ! ar t "$deb_file.part" >/dev/null 2>&1; then
      rm -f "$deb_file.part"
      fail "The downloaded file is not a valid DEB archive"
      return 1
    fi
    mv "$deb_file.part" "$deb_file"
    if [[ -n "$remote_fingerprint" ]]; then
      printf '%s' "$remote_fingerprint" >"$cache_fingerprint_file"
    fi
  fi

  tmp=$(mktemp -d) || return 1
  if ! (
    set -euo pipefail
    trap 'rm -rf "$tmp"' EXIT

    mkdir -p "$tmp/deb" "$tmp/root" "$tmp/control"
    cd "$tmp/deb"
    ar x "$deb_file"

    data_archive=$(find "$tmp/deb" -maxdepth 1 -type f -name 'data.tar.*' -print -quit)
    control_archive=$(find "$tmp/deb" -maxdepth 1 -type f -name 'control.tar.*' -print -quit)
    [[ -n "$data_archive" && -n "$control_archive" ]] || {
      echo "DEB is missing its data or control archive" >&2
      exit 1
    }

    tar -xf "$data_archive" -C "$tmp/root"
    tar -xf "$control_archive" -C "$tmp/control"
    control_file=$(find "$tmp/control" -type f -name control -print -quit)
    [[ -n "$control_file" ]] || {
      echo "Package control metadata is missing" >&2
      exit 1
    }
    package_version=$(awk -F ': ' '$1 == "Version" { print $2; exit }' "$control_file")
    [[ -n "$package_version" ]] || {
      echo "Could not read the version from the DEB metadata" >&2
      exit 1
    }
    echo "  Package version:   $package_version"

    app_source="$tmp/root/opt/OpenCode"
    [[ -d "$app_source" ]] || {
      echo "Unexpected DEB layout: /opt/OpenCode was not found" >&2
      exit 1
    }
    app_binary=""
    for item in ai.opencode ai.opencode.desktop @opencode-aidesktop @opencode-aidesktop-electron OpenCode; do
      if [[ -x "$app_source/$item" ]]; then
        app_binary="$app_source/$item"
        break
      fi
    done
    [[ -n "$app_binary" ]] || {
      echo "OpenCode Desktop executable was not found inside /opt/OpenCode" >&2
      exit 1
    }

    # Stage then swap the app directory, so a failed copy does not damage the
    # current installation. Keep app settings in the user's home directory.
    app_stage="/opt/.OpenCode.update-system.new.$$"
    app_backup="/opt/.OpenCode.update-system.old.$$"
    sudo rm -rf "$app_stage" "$app_backup"
    sudo cp -a "$app_source" "$app_stage"
    printf '%s\n' "$package_version" | sudo tee "$app_stage/.update-system-version" >/dev/null

    if [[ -e "$OPENCODE_DESKTOP_DIR" ]]; then
      sudo mv "$OPENCODE_DESKTOP_DIR" "$app_backup"
    fi
    if ! sudo mv "$app_stage" "$OPENCODE_DESKTOP_DIR"; then
      if [[ -e "$app_backup" ]]; then
        sudo mv "$app_backup" "$OPENCODE_DESKTOP_DIR" || true
      fi
      echo "Could not activate the new OpenCode Desktop directory" >&2
      exit 1
    fi
    sudo rm -rf "$app_backup"

    # Register app shortcuts and icons system-wide; no Debian package manager
    # is used on Void Linux.
    if [[ -d "$tmp/root/usr/share/applications" ]]; then
      sudo mkdir -p /usr/share/applications
      sudo cp -a "$tmp/root/usr/share/applications/." /usr/share/applications/
      if [[ ! -f "$tmp/root/usr/share/applications/OpenCode.desktop" ]]; then
        sudo rm -f /usr/share/applications/OpenCode.desktop
      fi
    fi
    if [[ -d "$tmp/root/usr/share/icons" ]]; then
      sudo mkdir -p /usr/share/icons
      sudo cp -a "$tmp/root/usr/share/icons/." /usr/share/icons/
    fi
    if [[ -d "$tmp/root/usr/share/metainfo" ]]; then
      sudo mkdir -p /usr/share/metainfo
      sudo cp -a "$tmp/root/usr/share/metainfo/." /usr/share/metainfo/
    fi
    # Some older package layouts use /usr/bin/OpenCode as their desktop entry.
    if [[ -e "$tmp/root/usr/bin/OpenCode" || -L "$tmp/root/usr/bin/OpenCode" ]]; then
      sudo cp -a "$tmp/root/usr/bin/OpenCode" /usr/bin/
    fi

    if command -v update-desktop-database >/dev/null 2>&1; then
      sudo update-desktop-database /usr/share/applications >/dev/null 2>&1 || true
    fi
    echo "Installed OpenCode Desktop $package_version"
  ); then
    rm -rf "$tmp"
    fail "Extraction or installation failed"
    return 1
  fi

  # Save the remote fingerprint only after the app and its launcher assets have
  # been installed. If a later step fails, the next run will retry.
  if [[ -n "$remote_fingerprint" ]]; then
    printf '%s' "$remote_fingerprint" | sudo tee "$OPENCODE_DESKTOP_FINGERPRINT_FILE" >/dev/null
  fi
  rm -rf "$tmp"
  ok "OpenCode Desktop installed/updated: $current → $(_opencode_desktop_installed_version)"
}
