#!/usr/bin/env bash
# modules/localsend.sh - LocalSend updater for Void Linux.
# Downloads the official upstream TAR.GZ release and installs it without DEB tooling.

LOCALSEND_API="https://api.github.com/repos/localsend/localsend/releases/latest"
LOCALSEND_DIR="/opt/LocalSend"
LOCALSEND_LAUNCHER="/usr/local/bin/localsend"
LOCALSEND_DESKTOP_FILE="/usr/share/applications/localsend.desktop"
LOCALSEND_CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/update-system/localsend"
LOCALSEND_VERSION_FILE="$LOCALSEND_DIR/.update-system-version"
LOCALSEND_FINGERPRINT_FILE="$LOCALSEND_DIR/.update-system-fingerprint"

_localsend_installed_version() {
    if [[ -r "$LOCALSEND_VERSION_FILE" ]]; then
        cat "$LOCALSEND_VERSION_FILE"
    elif [[ -x "$LOCALSEND_LAUNCHER" ]]; then
        printf '%s\n' "unknown"
    else
        printf '%s\n' "none"
    fi
}

_localsend_validate_archive() {
    local archive="$1"

    python3 - "$archive" <<'PY'
import posixpath
import sys
import tarfile

archive_path = sys.argv[1]
try:
    with tarfile.open(archive_path, "r:gz") as archive:
        members = archive.getmembers()
        if not members:
            raise ValueError("the archive is empty")

        for member in members:
            name = member.name
            if name.startswith("/") or ".." in name.split("/"):
                raise ValueError(f"unsafe archive path: {name!r}")

            if member.issym() or member.islnk():
                target = member.linkname
                if target.startswith("/"):
                    raise ValueError(f"absolute link target: {name!r} -> {target!r}")
                if member.issym():
                    resolved = posixpath.normpath(posixpath.join(posixpath.dirname(name), target))
                else:
                    resolved = posixpath.normpath(target)
                if resolved == ".." or resolved.startswith("../"):
                    raise ValueError(f"link escapes extraction directory: {name!r} -> {target!r}")
except (OSError, tarfile.TarError, ValueError) as error:
    print(f"Invalid LocalSend archive: {error}", file=sys.stderr)
    raise SystemExit(1)
PY
}

module_localsend_update() {
    step "LocalSend"

    local arch current_version release_json release_meta
    local release_tag remote_version asset_name asset_url asset_digest
    local remote_fingerprint installed_fingerprint expected_sha actual_sha
    local archive_file tmp extract_root app_binary binary_relative app_stage app_backup
    local launcher_tmp desktop_tmp icon_file icon_extension icon_destination

    case "$(uname -m)" in
        x86_64 | amd64) arch="x86-64" ;;
        aarch64 | arm64) arch="arm-64" ;;
        *)
            fail "LocalSend TAR.GZ is not available for architecture: $(uname -m)"
            return 1
            ;;
    esac

    for cmd in curl python3 tar find sha256sum awk sudo install; do
        command -v "$cmd" >/dev/null 2>&1 || {
            fail "Required command not found: $cmd"
            return 1
        }
    done

    current_version=$(_localsend_installed_version)
    echo "  Installed version: $current_version"
    echo "  Checking the latest stable GitHub release..."

    release_json=$(mktemp) || {
        fail "Could not create a temporary file for GitHub release metadata"
        return 1
    }
    release_meta=$(mktemp) || {
        rm -f "$release_json"
        fail "Could not create a temporary file for release information"
        return 1
    }

    if ! curl -fsSL \
        --proto '=https' \
        --proto-redir '=https' \
        --retry 2 \
        --connect-timeout 20 \
        --max-time 60 \
        -H "Accept: application/vnd.github+json" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        -H "User-Agent: update-system" \
        -o "$release_json" \
        "$LOCALSEND_API"; then
        rm -f "$release_json" "$release_meta"
        fail "Could not retrieve the latest LocalSend release from GitHub"
        return 1
    fi

    if ! python3 - "$release_json" "$arch" > "$release_meta" <<'PY'
import json
import re
import sys

metadata_path, architecture = sys.argv[1:]
with open(metadata_path, "r", encoding="utf-8") as handle:
    release = json.load(handle)

if release.get("draft") or release.get("prerelease"):
    raise SystemExit("GitHub returned a draft or prerelease instead of a stable release")

tag = release.get("tag_name", "")
version = tag.removeprefix("v")
if not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+(?:[-+][0-9A-Za-z.-]+)?", version):
    raise SystemExit(f"Unexpected LocalSend release tag: {tag!r}")

expected_name = f"LocalSend-{version}-linux-{architecture}.tar.gz"
matching = [asset for asset in release.get("assets", []) if asset.get("name") == expected_name]
if len(matching) != 1:
    raise SystemExit(f"Expected exactly one {expected_name} asset; found {len(matching)}")

asset = matching[0]
url = asset.get("browser_download_url", "")
expected_prefix = f"https://github.com/localsend/localsend/releases/download/{tag}/"
if not url.startswith(expected_prefix) or not url.endswith("/" + expected_name):
    raise SystemExit("The release asset URL does not match the expected LocalSend GitHub release")

digest = asset.get("digest") or ""
if digest:
    if not digest.startswith("sha256:"):
        raise SystemExit(f"Unsupported GitHub asset digest format: {digest}")
    digest = digest.removeprefix("sha256:").lower()
    if not re.fullmatch(r"[0-9a-f]{64}", digest):
        raise SystemExit("GitHub returned an invalid SHA-256 digest")

print(tag)
print(version)
print(expected_name)
print(url)
print(digest)
PY
    then
        rm -f "$release_json" "$release_meta"
        fail "Could not identify the official LocalSend TAR.GZ asset for $arch"
        return 1
    fi

    local -a release_info=()
    mapfile -t release_info < "$release_meta"
    rm -f "$release_json" "$release_meta"

    if [[ "${#release_info[@]}" -ne 5 ]]; then
        fail "GitHub release metadata is incomplete"
        return 1
    fi

    release_tag="${release_info[0]}"
    remote_version="${release_info[1]}"
    asset_name="${release_info[2]}"
    asset_url="${release_info[3]}"
    asset_digest="${release_info[4]}"

    # GitHub's release page publishes this digest. Keep a verified fallback for
    # the exact v1.18.2 asset supplied with this module request.
    if [[ -z "$asset_digest" && "$remote_version" == "1.18.2" ]]; then
        case "$arch" in
            x86-64) asset_digest="287690a9a8eb6da9c83cc97b3e3030ac67daf32a7331fcf307d0939300658d16" ;;
            arm-64) asset_digest="dd61f74f1ce3f4e25aca41cd3ce650d6a99353d7baba81a8139807275b88e606" ;;
        esac
    fi

    expected_sha="$asset_digest"
    remote_fingerprint="${release_tag}|${expected_sha:-sha256-unavailable}"
    installed_fingerprint=""
    if [[ -r "$LOCALSEND_FINGERPRINT_FILE" ]]; then
        installed_fingerprint=$(cat "$LOCALSEND_FINGERPRINT_FILE")
    fi

    echo "  Latest release:  $release_tag"
    echo "  Package asset:   $asset_name"

    if [[ "$current_version" == "$remote_version" && "$installed_fingerprint" == "$remote_fingerprint" ]]; then
        ok "LocalSend is up to date ($current_version)"
        return 0
    fi

    if [[ -z "$expected_sha" ]]; then
        warn "GitHub did not provide a SHA-256 digest; archive structure checks will be used"
    fi

    mkdir -p "$LOCALSEND_CACHE"
    archive_file="$LOCALSEND_CACHE/$asset_name"

    if [[ -s "$archive_file" ]]; then
        if ! _localsend_validate_archive "$archive_file"; then
            warn "Removing an invalid cached LocalSend archive"
            rm -f "$archive_file"
        elif [[ -n "$expected_sha" ]]; then
            actual_sha=$(sha256sum "$archive_file" | awk '{ print $1 }')
            if [[ "$actual_sha" != "$expected_sha" ]]; then
                warn "Cached archive checksum does not match the release; downloading again"
                rm -f "$archive_file"
            fi
        fi
    fi

    if [[ ! -s "$archive_file" ]]; then
        echo "  Downloading LocalSend $remote_version..."
        if ! curl -fL \
            --proto '=https' \
            --proto-redir '=https' \
            --retry 2 \
            --connect-timeout 20 \
            --max-time 1200 \
            --progress-bar \
            -o "$archive_file.part" \
            "$asset_url"; then
            rm -f "$archive_file.part"
            fail "LocalSend download failed"
            return 1
        fi

        if ! _localsend_validate_archive "$archive_file.part"; then
            rm -f "$archive_file.part"
            fail "Downloaded file is not a safe, valid TAR.GZ archive"
            return 1
        fi

        if [[ -n "$expected_sha" ]]; then
            actual_sha=$(sha256sum "$archive_file.part" | awk '{ print $1 }')
            if [[ "$actual_sha" != "$expected_sha" ]]; then
                rm -f "$archive_file.part"
                fail "LocalSend SHA-256 verification failed"
                return 1
            fi
            echo "  SHA-256 checksum verified"
        fi

        mv "$archive_file.part" "$archive_file"
    fi

    tmp=$(mktemp -d) || {
        fail "Could not create a temporary extraction directory"
        return 1
    }
    extract_root="$tmp/root"
    mkdir -p "$extract_root"

    if ! tar -xzf "$archive_file" --no-same-owner -C "$extract_root"; then
        rm -rf "$tmp"
        fail "Could not extract the LocalSend archive"
        return 1
    fi

    app_binary=$(find "$extract_root" -type f -name 'localsend_app' -print -quit)
    if [[ -z "$app_binary" ]]; then
        rm -rf "$tmp"
        fail "The archive does not contain the expected localsend_app executable"
        return 1
    fi

    binary_relative="${app_binary#"$extract_root"/}"
    if [[ "$binary_relative" == "$app_binary" || "$binary_relative" == *$'\n'* ]]; then
        rm -rf "$tmp"
        fail "Could not determine the LocalSend executable path inside the archive"
        return 1
    fi
    chmod u+x "$app_binary"

    if command -v ldd >/dev/null 2>&1; then
        local missing_libraries
        missing_libraries=$(ldd "$app_binary" 2>/dev/null | awk '/not found/ && !seen[$1]++ { print $1 }' || true)
        if [[ -n "$missing_libraries" ]]; then
            warn "LocalSend has unresolved runtime libraries on this system:"
            while IFS= read -r library; do
                [[ -n "$library" ]] && echo "    $library"
            done <<< "$missing_libraries"
            warn "Install the matching Void packages with xbps-install before launching LocalSend"
        fi
    fi

    if declare -F start_sudo_keepalive >/dev/null 2>&1; then
        start_sudo_keepalive
    fi
    if ! sudo -v; then
        rm -rf "$tmp"
        fail "sudo authentication failed"
        return 1
    fi

    app_stage="/opt/.LocalSend.update-system.new.$$"
    app_backup="/opt/.LocalSend.update-system.old.$$"
    sudo rm -rf "$app_stage" "$app_backup"

    if ! sudo cp -a --no-preserve=ownership "$extract_root" "$app_stage"; then
        rm -rf "$tmp"
        sudo rm -rf "$app_stage"
        fail "Could not stage the new LocalSend application"
        return 1
    fi

    if ! printf '%s\n' "$remote_version" | sudo tee "$app_stage/.update-system-version" >/dev/null || \
       ! printf '%s\n' "$remote_fingerprint" | sudo tee "$app_stage/.update-system-fingerprint" >/dev/null || \
       ! sudo chown -R root:root "$app_stage"; then
        rm -rf "$tmp"
        sudo rm -rf "$app_stage"
        fail "Could not prepare the staged LocalSend application"
        return 1
    fi

    # Keep the executable path stable so desktop entries and user settings survive upgrades.
    if [[ -e "$LOCALSEND_DIR" || -L "$LOCALSEND_DIR" ]]; then
        if ! sudo mv "$LOCALSEND_DIR" "$app_backup"; then
            rm -rf "$tmp"
            sudo rm -rf "$app_stage"
            fail "Could not move the existing LocalSend installation"
            return 1
        fi
    fi

    if ! sudo mv "$app_stage" "$LOCALSEND_DIR"; then
        if [[ -e "$app_backup" ]]; then
            sudo mv "$app_backup" "$LOCALSEND_DIR" || true
        fi
        rm -rf "$tmp"
        sudo rm -rf "$app_stage"
        fail "Could not activate the new LocalSend installation; rollback was attempted"
        return 1
    fi

    # Generate a stable command-line launcher and a desktop entry for desktop environments.
    launcher_tmp="$tmp/localsend-launcher"
    desktop_tmp="$tmp/localsend.desktop"
    printf '#!/bin/sh\nexec %q "$@"\n' "$LOCALSEND_DIR/$binary_relative" > "$launcher_tmp"
    chmod 0755 "$launcher_tmp"

    cat > "$desktop_tmp" <<'DESKTOP'
[Desktop Entry]
Version=1.0
Type=Application
Name=LocalSend
Comment=Share files to nearby devices on your local network
Exec=/usr/local/bin/localsend
Icon=localsend
Terminal=false
Categories=Network;FileTransfer;
StartupNotify=true
DESKTOP

    if ! sudo install -D -m 0755 "$launcher_tmp" "$LOCALSEND_LAUNCHER" || \
       ! sudo install -D -m 0644 "$desktop_tmp" "$LOCALSEND_DESKTOP_FILE"; then
        warn "LocalSend was installed, but its launcher or desktop entry could not be refreshed"
    fi

    # Install a bundled upstream icon when the archive provides one.
    icon_file=$(find "$extract_root" -type f \( -iname 'localsend.png' -o -iname 'localsend.svg' -o -iname 'logo-256.png' -o -iname 'logo-512.png' \) -print -quit)
    if [[ -n "$icon_file" ]]; then
        icon_extension="${icon_file##*.}"
        icon_extension="${icon_extension,,}"
        if [[ "$icon_extension" == "svg" ]]; then
            icon_destination="/usr/share/icons/hicolor/scalable/apps/localsend.svg"
        else
            icon_destination="/usr/share/icons/hicolor/256x256/apps/localsend.png"
        fi
        sudo install -D -m 0644 "$icon_file" "$icon_destination" || \
            warn "Could not install the bundled LocalSend icon"
    fi

    sudo rm -rf "$app_backup"
    rm -rf "$tmp"

    if command -v update-desktop-database >/dev/null 2>&1; then
        sudo update-desktop-database /usr/share/applications >/dev/null 2>&1 || true
    fi

    ok "LocalSend updated: $current_version → $(_localsend_installed_version)"
}
