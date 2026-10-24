#!/usr/bin/env bash
# modules/vscode.sh - Official Visual Studio Code stable updater for Void Linux.
# Downloads Microsoft's DEB package and extracts it without invoking dpkg.

VSCODE_URL="https://code.visualstudio.com/sha/download?build=stable&os=linux-deb-x64"
VSCODE_DIR="/usr/share/code"
VSCODE_VERSION_FILE="$VSCODE_DIR/.update-system-version"
VSCODE_FINGERPRINT_FILE="$VSCODE_DIR/.update-system-fingerprint"
VSCODE_CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/update-system/vscode"

_vscode_remote_fingerprint() {
  local headers final_url etag modified length
  headers=$(mktemp) || return 1

  if ! final_url=$(curl -fsSLI --retry 1 --connect-timeout 20 --max-time 60 \
    -D "$headers" -o /dev/null -w '%{url_effective}' "$VSCODE_URL"); then
    rm -f "$headers"
    return 1
  fi

  etag=$(grep -i '^etag:' "$headers" | tail -n 1 | sed -E 's/^[^:]*:[[:space:]]*//; s/\r$//')
  modified=$(grep -i '^last-modified:' "$headers" | tail -n 1 | sed -E 's/^[^:]*:[[:space:]]*//; s/\r$//')
  length=$(grep -i '^content-length:' "$headers" | tail -n 1 | sed -E 's/^[^:]*:[[:space:]]*//; s/\r$//')
  rm -f "$headers"

  # The final redirect URL normally contains Microsoft's version/build-specific artifact ID.
  [[ -n "$final_url$etag$modified$length" ]] || return 1
  printf 'url=%s\netag=%s\nlast-modified=%s\ncontent-length=%s\n' \
    "$final_url" "$etag" "$modified" "$length"
}

_vscode_installed_version() {
  if [[ -r "$VSCODE_VERSION_FILE" ]]; then
    cat "$VSCODE_VERSION_FILE"
  elif command -v code >/dev/null 2>&1; then
    code --version 2>/dev/null | head -n 1 || printf '%s\n' unknown
  elif [[ -x "$VSCODE_DIR/code" ]]; then
    "$VSCODE_DIR/code" --version 2>/dev/null | head -n 1 || printf '%s\n' unknown
  elif [[ -d "$VSCODE_DIR" ]]; then
    printf '%s\n' unknown
  else
    printf '%s\n' none
  fi
}

module_vscode_update() {
  step "Visual Studio Code"

  local current remote_fingerprint installed_fingerprint deb_file cache_fingerprint_file
  local tmp data_archive control_archive control_file package_name package_version
  local app_source app_stage app_backup entry bin_stage target source_item relative_item target_item

  case "$(uname -m)" in
    x86_64 | amd64) ;;
    *) fail "The official download URL is Linux x64; unsupported architecture: $(uname -m)"; return 1 ;;
  esac

  for cmd in curl ar tar awk grep sed find; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      fail "Required command not found: $cmd"
      return 1
    fi
  done
  if ! command -v sudo >/dev/null 2>&1; then
    fail "Required command not found: sudo"
    return 1
  fi

  current=$(_vscode_installed_version)
  echo "  Installed version: $current"

  remote_fingerprint=$(_vscode_remote_fingerprint 2>/dev/null || true)
  installed_fingerprint=""
  if [[ -r "$VSCODE_FINGERPRINT_FILE" ]]; then
    installed_fingerprint=$(cat "$VSCODE_FINGERPRINT_FILE")
  fi

  if [[ -n "$remote_fingerprint" && "$remote_fingerprint" == "$installed_fingerprint" && "$current" != "none" && "$current" != "unknown" ]]; then
    ok "Visual Studio Code is up to date ($current)"
    return 0
  fi
  if [[ -z "$remote_fingerprint" ]]; then
    warn "Could not read reliable remote update metadata; downloading the stable package directly"
  fi

  mkdir -p "$VSCODE_CACHE"
  deb_file="$VSCODE_CACHE/code-stable-amd64.deb"
  cache_fingerprint_file="$deb_file.fingerprint"

  if [[ -n "$remote_fingerprint" && -s "$deb_file" && -r "$cache_fingerprint_file" && "$(cat "$cache_fingerprint_file")" == "$remote_fingerprint" ]]; then
    echo "  Using cached package for the current stable build"
  else
    rm -f "$deb_file" "$cache_fingerprint_file" "$deb_file.part"
    echo "  Downloading the official stable DEB..."
    if ! curl -fL --retry 2 --connect-timeout 20 --max-time 900 --progress-bar \
      -o "$deb_file.part" "$VSCODE_URL"; then
      rm -f "$deb_file.part"
      fail "Visual Studio Code download failed"
      return 1
    fi
    if ! ar t "$deb_file.part" >/dev/null 2>&1; then
      rm -f "$deb_file.part"
      fail "The downloaded file is not a valid DEB archive"
      return 1
    fi
    mv "$deb_file.part" "$deb_file"
    if [[ -n "$remote_fingerprint" ]]; then
      printf '%s' "$remote_fingerprint" > "$cache_fingerprint_file"
    fi
  fi

  tmp=$(mktemp -d) || { fail "Could not create a temporary directory"; return 1; }
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
    [[ -n "$control_file" ]] || { echo "Package control metadata is missing" >&2; exit 1; }

    package_name=$(awk -F ': ' '$1 == "Package" { print $2; exit }' "$control_file")
    package_version=$(awk -F ': ' '$1 == "Version" { print $2; exit }' "$control_file")
    [[ "$package_name" == "code" ]] || { echo "Unexpected package name: ${package_name:-missing}" >&2; exit 1; }
    [[ -n "$package_version" ]] || { echo "Could not read the package version from DEB metadata" >&2; exit 1; }

    echo "  Package version:   $package_version"
    app_source="$tmp/root/usr/share/code"
    [[ -d "$app_source" ]] || { echo "Unexpected DEB layout: /usr/share/code was not found" >&2; exit 1; }
    [[ -x "$app_source/code" ]] || { echo "VS Code executable was not found in /usr/share/code" >&2; exit 1; }

    app_stage="/usr/share/.code.update-system.new.$$"
    app_backup="/usr/share/.code.update-system.old.$$"
    sudo rm -rf -- "$app_stage" "$app_backup"
    sudo cp -a "$app_source" "$app_stage"
    sudo chown -R root:root "$app_stage"
    printf '%s\n' "$package_version" | sudo tee "$app_stage/.update-system-version" >/dev/null

    # Merge package-provided integration files without replacing unrelated files
    # in shared directories. Correct ownership because extraction runs as the user.
    if [[ -d "$tmp/root/usr/share" ]]; then
      while IFS= read -r -d '' entry; do
        [[ "${entry##*/}" == "code" ]] && continue
        if [[ -d "$entry" ]]; then
          target="/usr/share/${entry##*/}"
          sudo mkdir -p "$target"
          sudo cp -a "$entry/." "$target/"
        else
          sudo cp -a "$entry" /usr/share/
        fi
        while IFS= read -r -d '' source_item; do
          relative_item="${source_item#"$tmp/root/usr/share/"}"
          target_item="/usr/share/$relative_item"
          if [[ -e "$target_item" || -L "$target_item" ]]; then
            sudo chown -h root:root "$target_item"
          fi
        done < <(find "$entry" -print0)
      done < <(find "$tmp/root/usr/share" -mindepth 1 -maxdepth 1 -print0)
    fi

    # Replace /usr/bin/code atomically if this DEB contains the launcher.
    if [[ -e "$tmp/root/usr/bin/code" || -L "$tmp/root/usr/bin/code" ]]; then
      bin_stage="/usr/bin/.code.update-system.new.$$"
      sudo rm -f -- "$bin_stage"
      sudo cp -a "$tmp/root/usr/bin/code" "$bin_stage"
      sudo chown -h root:root "$bin_stage"
      sudo mv -Tf "$bin_stage" /usr/bin/code
    fi

    if [[ -e "$VSCODE_DIR" || -L "$VSCODE_DIR" ]]; then
      sudo mv "$VSCODE_DIR" "$app_backup"
    fi
    if ! sudo mv "$app_stage" "$VSCODE_DIR"; then
      if [[ -e "$app_backup" || -L "$app_backup" ]]; then
        sudo mv "$app_backup" "$VSCODE_DIR" || true
      fi
      echo "Could not activate the new Visual Studio Code directory" >&2
      exit 1
    fi
    sudo rm -rf -- "$app_backup"

    if command -v update-desktop-database >/dev/null 2>&1; then
      sudo update-desktop-database /usr/share/applications >/dev/null 2>&1 || true
    fi
    if command -v update-mime-database >/dev/null 2>&1 && [[ -d /usr/share/mime ]]; then
      sudo update-mime-database /usr/share/mime >/dev/null 2>&1 || true
    fi
    if command -v gtk-update-icon-cache >/dev/null 2>&1 && [[ -d /usr/share/icons/hicolor ]]; then
      sudo gtk-update-icon-cache -f /usr/share/icons/hicolor >/dev/null 2>&1 || true
    fi

    echo "Installed Visual Studio Code $package_version"
  ); then
    rm -rf "$tmp"
    fail "Extraction or installation failed"
    return 1
  fi

  if [[ -n "$remote_fingerprint" ]]; then
    printf '%s' "$remote_fingerprint" | sudo tee "$VSCODE_FINGERPRINT_FILE" >/dev/null
  fi
  rm -rf "$tmp"
  ok "Visual Studio Code installed/updated: $current → $(_vscode_installed_version)"
}
