#!/usr/bin/env bash
# modules/claude-desktop.sh - Claude Desktop updater for Void Linux.
# Downloads the official Claude Desktop DEB published with the
# aaddrick/claude-desktop-debian releases and extracts it without dpkg.

CLAUDE_DESKTOP_API="https://api.github.com/repos/aaddrick/claude-desktop-debian/releases/latest"
CLAUDE_DESKTOP_DIR="/usr/lib/claude-desktop"
CLAUDE_DESKTOP_CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/update-system/claude-desktop"
CLAUDE_DESKTOP_VERSION_FILE="$CLAUDE_DESKTOP_DIR/.update-system-version"
CLAUDE_DESKTOP_FINGERPRINT_FILE="$CLAUDE_DESKTOP_DIR/.update-system-fingerprint"

_claude_desktop_extract_archive() {
    local archive="$1"
    local destination="$2"

    case "$archive" in
        *.tar.zst | *.tar.zstd)
            command -v zstd >/dev/null 2>&1 || {
                echo "The zstd command is required to extract: $(basename "$archive")" >&2
                return 1
            }
            zstd -dc "$archive" | tar -xf - -C "$destination"
            ;;
        *.tar.xz)
            tar -xJf "$archive" -C "$destination"
            ;;
        *.tar.gz | *.tgz)
            tar -xzf "$archive" -C "$destination"
            ;;
        *.tar.bz2)
            tar -xjf "$archive" -C "$destination"
            ;;
        *.tar)
            tar -xf "$archive" -C "$destination"
            ;;
        *)
            echo "Unsupported DEB archive format: $(basename "$archive")" >&2
            return 1
            ;;
    esac
}

_claude_desktop_installed_version() {
    if [[ -r "$CLAUDE_DESKTOP_VERSION_FILE" ]]; then
        cat "$CLAUDE_DESKTOP_VERSION_FILE"
    elif [[ -d "$CLAUDE_DESKTOP_DIR" ]]; then
        printf '%s\n' "unknown"
    else
        printf '%s\n' "none"
    fi
}

module_claude-desktop_update() {
    step "Claude Desktop"

    local deb_arch icon_dir
    local -a release_info=()
    local current_version release_json release_meta
    local release_tag asset_name asset_url asset_digest remote_version remote_fingerprint
    local installed_fingerprint deb_file expected_sha actual_sha
    local tmp deb_dir root_dir control_dir data_archive control_archive control_file
    local package_name package_version package_arch package_depends app_source app_binary
    local app_stage app_backup

    case "$(uname -m)" in
        x86_64 | amd64) deb_arch="amd64" ;;
        aarch64 | arm64) deb_arch="arm64" ;;
        *)
            fail "Claude Desktop DEB is not available for architecture: $(uname -m)"
            return 1
            ;;
    esac

    for cmd in curl python3 ar tar find awk grep sha256sum sudo; do
        command -v "$cmd" >/dev/null 2>&1 || {
            fail "Required command not found: $cmd"
            return 1
        }
    done

    current_version=$(_claude_desktop_installed_version)
    echo "  Installed version: $current_version"

    release_json=$(mktemp) || {
        fail "Could not create a temporary file for GitHub release metadata"
        return 1
    }
    release_meta=$(mktemp) || {
        rm -f "$release_json"
        fail "Could not create a temporary file for release information"
        return 1
    }

    echo "  Checking the latest GitHub release..."
    if ! curl -fsSL \
        --retry 2 \
        --connect-timeout 20 \
        --max-time 60 \
        -H "Accept: application/vnd.github+json" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        -H "User-Agent: update-system" \
        -o "$release_json" \
        "$CLAUDE_DESKTOP_API"; then
        rm -f "$release_json" "$release_meta"
        fail "Could not retrieve the latest Claude Desktop release from GitHub"
        return 1
    fi

    if ! python3 - "$release_json" "$deb_arch" > "$release_meta" <<'PY'
import json
import re
import sys

metadata_path, architecture = sys.argv[1:]
with open(metadata_path, "r", encoding="utf-8") as handle:
    release = json.load(handle)

if release.get("draft") or release.get("prerelease"):
    raise SystemExit("GitHub returned a draft or prerelease instead of a stable release")

pattern = re.compile(rf"^claude-desktop_(.+)_{re.escape(architecture)}\.deb$")
assets = release.get("assets", [])
matching = []
for asset in assets:
    name = asset.get("name", "")
    match = pattern.fullmatch(name)
    if match:
        matching.append((asset, match.group(1)))

if not matching:
    raise SystemExit(f"No official claude-desktop DEB found for {architecture}")

# A release should publish one official DEB per architecture. Refuse ambiguity.
if len(matching) != 1:
    raise SystemExit(f"Expected one {architecture} DEB asset, found {len(matching)}")

asset, version = matching[0]
url = asset.get("browser_download_url", "")
if not url.startswith("https://github.com/aaddrick/claude-desktop-debian/releases/download/"):
    raise SystemExit("The release asset URL is not from the expected GitHub repository")

digest = asset.get("digest") or ""
if digest and not digest.startswith("sha256:"):
    raise SystemExit(f"Unsupported asset digest format: {digest}")
if digest:
    digest = digest.removeprefix("sha256:")
    if not re.fullmatch(r"[0-9a-fA-F]{64}", digest):
        raise SystemExit("GitHub returned an invalid SHA-256 digest")

print(release.get("tag_name", ""))
print(asset["name"])
print(url)
print(digest)
print(version)
PY
    then
        rm -f "$release_json" "$release_meta"
        fail "Could not identify the official Claude Desktop DEB in the latest GitHub release"
        return 1
    fi

    mapfile -t release_info < "$release_meta"
    rm -f "$release_json" "$release_meta"

    if [[ "${#release_info[@]}" -ne 5 ]]; then
        fail "GitHub release metadata is incomplete"
        return 1
    fi

    release_tag="${release_info[0]}"
    asset_name="${release_info[1]}"
    asset_url="${release_info[2]}"
    asset_digest="${release_info[3]}"
    remote_version="${release_info[4]}"

    if [[ ! "$remote_version" =~ ^[0-9A-Za-z.+~_-]+$ ]]; then
        fail "Unexpected Claude Desktop version string: $remote_version"
        return 1
    fi

    expected_sha="$asset_digest"
    remote_fingerprint="${remote_version}|${expected_sha:-unavailable}"
    installed_fingerprint=""
    if [[ -r "$CLAUDE_DESKTOP_FINGERPRINT_FILE" ]]; then
        installed_fingerprint=$(cat "$CLAUDE_DESKTOP_FINGERPRINT_FILE")
    fi

    echo "  Latest release:    $release_tag"
    echo "  Package version:   $remote_version"
    echo "  Package asset:     $asset_name"

    if [[ "$current_version" == "$remote_version" && "$installed_fingerprint" == "$remote_fingerprint" ]]; then
        ok "Claude Desktop is up to date ($current_version)"
        return 0
    fi

    if [[ -z "$expected_sha" ]]; then
        warn "GitHub did not provide an asset SHA-256 digest; HTTPS and DEB structure checks will be used"
    fi

    mkdir -p "$CLAUDE_DESKTOP_CACHE"
    deb_file="$CLAUDE_DESKTOP_CACHE/$asset_name"

    if [[ -s "$deb_file" ]]; then
        if ! ar t "$deb_file" >/dev/null 2>&1; then
            warn "Removing an invalid cached DEB archive"
            rm -f "$deb_file"
        elif [[ -n "$expected_sha" ]]; then
            actual_sha=$(sha256sum "$deb_file" | awk '{ print $1 }')
            if [[ "$actual_sha" != "$expected_sha" ]]; then
                warn "Cached package checksum does not match the GitHub release; downloading again"
                rm -f "$deb_file"
            fi
        fi
    fi

    if [[ ! -s "$deb_file" ]]; then
        echo "  Downloading the official Claude Desktop DEB..."
        if ! curl -fL \
            --retry 2 \
            --connect-timeout 20 \
            --max-time 1200 \
            --progress-bar \
            -o "$deb_file.part" \
            "$asset_url"; then
            rm -f "$deb_file.part"
            fail "Claude Desktop download failed"
            return 1
        fi

        if ! ar t "$deb_file.part" >/dev/null 2>&1; then
            rm -f "$deb_file.part"
            fail "The downloaded file is not a valid DEB archive"
            return 1
        fi

        if [[ -n "$expected_sha" ]]; then
            actual_sha=$(sha256sum "$deb_file.part" | awk '{ print $1 }')
            if [[ "$actual_sha" != "$expected_sha" ]]; then
                rm -f "$deb_file.part"
                fail "Claude Desktop SHA-256 verification failed"
                return 1
            fi
        fi

        mv "$deb_file.part" "$deb_file"
    fi

    tmp=$(mktemp -d) || {
        fail "Could not create a temporary extraction directory"
        return 1
    }
    deb_dir="$tmp/deb"
    root_dir="$tmp/root"
    control_dir="$tmp/control"
    mkdir -p "$deb_dir" "$root_dir" "$control_dir"

    if ! (cd "$deb_dir" && ar x "$deb_file"); then
        rm -rf "$tmp"
        fail "Could not extract the DEB container"
        return 1
    fi

    data_archive=$(find "$deb_dir" -maxdepth 1 -type f -name 'data.tar.*' -print -quit)
    control_archive=$(find "$deb_dir" -maxdepth 1 -type f -name 'control.tar.*' -print -quit)
    if [[ -z "$data_archive" || -z "$control_archive" ]]; then
        rm -rf "$tmp"
        fail "DEB is missing its data or control archive"
        return 1
    fi

    if ! _claude_desktop_extract_archive "$data_archive" "$root_dir" || \
       ! _claude_desktop_extract_archive "$control_archive" "$control_dir"; then
        rm -rf "$tmp"
        fail "Could not extract Claude Desktop package contents"
        return 1
    fi

    control_file=$(find "$control_dir" -type f -name control -print -quit)
    if [[ -z "$control_file" ]]; then
        rm -rf "$tmp"
        fail "Claude Desktop package control metadata is missing"
        return 1
    fi

    package_name=$(awk -F ': ' '$1 == "Package" { print $2; exit }' "$control_file")
    package_version=$(awk -F ': ' '$1 == "Version" { print $2; exit }' "$control_file")
    package_arch=$(awk -F ': ' '$1 == "Architecture" { print $2; exit }' "$control_file")
    package_depends=$(awk '
        /^Depends:/ {
            active = 1
            sub(/^Depends:[[:space:]]*/, "")
            value = $0
            next
        }
        /^[^[:space:]]/ {
            if (active) exit
        }
        active {
            sub(/^[[:space:]]+/, "")
            value = value " " $0
        }
        END {
            gsub(/[[:space:]]+/, " ", value)
            print value
        }
    ' "$control_file")

    if [[ "$package_name" != "claude-desktop" ]]; then
        rm -rf "$tmp"
        fail "Unexpected DEB package name: ${package_name:-unknown}; expected claude-desktop"
        return 1
    fi

    if [[ "$package_arch" != "$deb_arch" && "$package_arch" != "all" ]]; then
        rm -rf "$tmp"
        fail "Package architecture mismatch: expected $deb_arch, got ${package_arch:-unknown}"
        return 1
    fi

    app_source="$root_dir/usr/lib/claude-desktop"
    if [[ ! -d "$app_source" ]]; then
        rm -rf "$tmp"
        fail "Unexpected DEB layout: /usr/lib/claude-desktop was not found"
        return 1
    fi

    app_binary=$(find "$app_source" -type f -perm /111 -print -quit)
    if [[ -z "$app_binary" ]]; then
        rm -rf "$tmp"
        fail "No executable was found inside /usr/lib/claude-desktop"
        return 1
    fi

    echo "  Debian package:   ${package_version:-unknown}"
    if [[ -n "$package_depends" ]]; then
        echo "  Declared Depends: $package_depends"
        warn "Void Linux will not resolve Debian Depends automatically; missing runtime libraries must be installed with xbps"
    fi

    app_stage="/usr/lib/.claude-desktop.update-system.new.$$"
    app_backup="/usr/lib/.claude-desktop.update-system.old.$$"

    if declare -F start_sudo_keepalive >/dev/null 2>&1; then
        start_sudo_keepalive
    fi

    if ! sudo -v; then
        rm -rf "$tmp"
        fail "sudo authentication failed"
        return 1
    fi

    sudo rm -rf "$app_stage" "$app_backup"
    if ! sudo cp -a --no-preserve=ownership "$app_source" "$app_stage"; then
        rm -rf "$tmp"
        sudo rm -rf "$app_stage"
        fail "Could not stage the new Claude Desktop application"
        return 1
    fi

    if ! printf '%s\n' "$remote_version" | sudo tee "$app_stage/.update-system-version" >/dev/null ||
       ! printf '%s\n' "$remote_fingerprint" | sudo tee "$app_stage/.update-system-fingerprint" >/dev/null ||
       ! sudo chown -R root:root "$app_stage"; then
        rm -rf "$tmp"
        sudo rm -rf "$app_stage"
        fail "Could not prepare the staged Claude Desktop application"
        return 1
    fi

    # Keep the package's launcher, desktop entry, icons, and other support files.
    # The application directory itself is installed separately and atomically below.
    rm -rf "$root_dir/usr/lib/claude-desktop"
    if ! sudo cp -a --no-preserve=ownership "$root_dir/." /; then
        rm -rf "$tmp"
        sudo rm -rf "$app_stage"
        fail "Could not install Claude Desktop support files"
        return 1
    fi

    if [[ -e "$CLAUDE_DESKTOP_DIR" || -L "$CLAUDE_DESKTOP_DIR" ]]; then
        if ! sudo mv "$CLAUDE_DESKTOP_DIR" "$app_backup"; then
            rm -rf "$tmp"
            sudo rm -rf "$app_stage"
            fail "Could not move the existing Claude Desktop installation"
            return 1
        fi
    fi

    if ! sudo mv "$app_stage" "$CLAUDE_DESKTOP_DIR"; then
        if [[ -e "$app_backup" ]]; then
            sudo mv "$app_backup" "$CLAUDE_DESKTOP_DIR" || true
        fi
        rm -rf "$tmp"
        sudo rm -rf "$app_stage"
        fail "Could not activate the new Claude Desktop installation; rollback was attempted"
        return 1
    fi

    sudo rm -rf "$app_backup"
    rm -rf "$tmp"

    if command -v update-desktop-database >/dev/null 2>&1; then
        sudo update-desktop-database /usr/share/applications >/dev/null 2>&1 || true
    fi
    if command -v gtk-update-icon-cache >/dev/null 2>&1; then
        while IFS= read -r -d '' icon_dir; do
            sudo gtk-update-icon-cache -f "$icon_dir" >/dev/null 2>&1 || true
        done < <(find /usr/share/icons -mindepth 1 -maxdepth 1 -type d -print0 2>/dev/null)
    fi

    ok "Claude Desktop updated: $current_version → $(_claude_desktop_installed_version)"
}
