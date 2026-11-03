#!/usr/bin/env bash
# modules/artcraft.sh - ArtCraft Launcher updater for Void Linux

ARTCRAFT_API="https://api.github.com/repos/storytold/craft-launcher/releases/latest"
ARTCRAFT_RELEASES="https://github.com/storytold/craft-launcher/releases/download"
ARTCRAFT_DIR="$HOME/.local/opt/artcraft"
ARTCRAFT_CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/update-system/artcraft"

_artcraft_latest_release() {
  curl -fsSL --max-time 30 "$ARTCRAFT_API" |
    grep -oP '"tag_name":\s*"\K[^"]+' |
    head -1
}

_artcraft_installed_version() {
  if [[ -x "$ARTCRAFT_DIR/bin/artcraft-launcher" ]]; then
    "$ARTCRAFT_DIR/bin/artcraft-launcher" --version 2>&1 |
      grep -oP '\d+\.\d+\.\d+' |
      head -1 || true
  else
    printf '%s\n' "none"
  fi
}

module_artcraft_update() {
  step "ArtCraft Launcher"

  local arch tag version asset url checksum_url sums_file
  local deb_file tmp expected actual

  case "$(uname -m)" in
  x86_64) arch="x86_64" ;;
  aarch64 | arm64) arch="aarch64" ;;
  *)
    fail "Unsupported architecture: $(uname -m)"
    return 1
    ;;
  esac

  tag=$(_artcraft_latest_release) || {
    fail "Could not fetch latest ArtCraft release"
    return 1
  }

  [[ -n "$tag" ]] || {
    fail "Empty release tag"
    return 1
  }

  version="${tag#v}"
  asset="artcraft-launcher-${version}-linux-${arch}.deb"
  url="${ARTCRAFT_RELEASES}/${tag}/${asset}"
  checksum_url="${ARTCRAFT_RELEASES}/${tag}/SHA256SUMS.txt"

  mkdir -p "$ARTCRAFT_CACHE"

  deb_file="$ARTCRAFT_CACHE/$asset"
  sums_file="$ARTCRAFT_CACHE/SHA256SUMS.txt"

  echo "  Latest version: $version"
  echo "  Architecture:   $arch"

  curl -fLsS --max-time 30 "$checksum_url" -o "$sums_file" || {
    fail "Could not download official checksums"
    return 1
  }

  expected=$(
    awk -v file="$asset" '
      $2 == file || $2 == "*" file {
        print $1
        exit
      }
    ' "$sums_file"
  )

  [[ "$expected" =~ ^[[:xdigit:]]{64}$ ]] || {
    fail "No valid SHA256 found for $asset"
    return 1
  }

  if [[ -f "$deb_file" ]] &&
    ! verify_sha256 "$deb_file" "$expected"; then
    rm -f "$deb_file"
  fi

  if [[ ! -s "$deb_file" ]]; then
    echo "  Downloading $asset..."
    curl -fL --retry 2 --max-time 600 \
      -o "$deb_file.part" "$url" || {
      rm -f "$deb_file.part"
      fail "Download failed"
      return 1
    }

    if ! verify_sha256 "$deb_file.part" "$expected"; then
      rm -f "$deb_file.part"
      fail "SHA256 verification failed"
      return 1
    fi

    mv "$deb_file.part" "$deb_file"
  fi

  ok "SHA256 verified"

  tmp=$(mktemp -d) || return 1

  if ! (
    set -e
    trap 'rm -rf "$tmp"' EXIT

    cd "$tmp"
    ar x "$deb_file"

    local data_tar
    data_tar=$(find . -maxdepth 1 -name 'data.tar.*' -print -quit)

    [[ -n "$data_tar" ]] || {
      echo "Missing data archive" >&2
      exit 1
    }

    mkdir extracted
    tar -xf "$data_tar" -C extracted

    local binary
    binary=$(find extracted -type f \
      -path '*/bin/artcraft-launcher' -print -quit)

    [[ -n "$binary" ]] || {
      echo "Launcher binary not found in package" >&2
      exit 1
    }

    mkdir -p "$ARTCRAFT_DIR"
    cp -a extracted/. "$ARTCRAFT_DIR/"

    chmod +x "$ARTCRAFT_DIR/bin/artcraft-launcher"

    echo "  Installed to: $ARTCRAFT_DIR"
  ); then
    rm -rf "$tmp"
    fail "Extraction or installation failed"
    return 1
  fi

  rm -rf "$tmp"
  ok "ArtCraft Launcher $version installed"
}
