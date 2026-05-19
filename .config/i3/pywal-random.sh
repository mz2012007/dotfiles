#!/usr/bin/env bash
# pywal-random.sh
# يختار صورة عشوائية من مجلد ويشغل feh + wal عليها
# usage: pywal-random.sh /path/to/wallpapers [--feh-opts="--bg-scale"]

set -euo pipefail

WALLDIR="${1:-$HOME/backgrounds}"
FEH_OPTS="${2:---bg-scale}"

# Check dependencies
for cmd in find shuf feh wal; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Error: required command '$cmd' not found. Please install it." >&2
    exit 2
  fi
done

# Find image files
mapfile -d '' files < <(find "$WALLDIR" -type f \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.bmp' \) -print0)

if [ "${#files[@]}" -eq 0 ]; then
  echo "No images found in '$WALLDIR'." >&2
  exit 3
fi

# Pick random image
idx=$((RANDOM % ${#files[@]}))
IMG="${files[$idx]}"

echo "Using wallpaper: $IMG"

# Set wallpaper with feh (so background is set before wal runs)
feh $FEH_OPTS "$IMG"

# Run pywal (wal) on selected image
# -n : don't use cache? (optional) -- keeping simple: basic call
wal -i "$IMG"

# Optional: source wal colors into this shell environment (useful for custom scripts)
if [ -f "${HOME}/.cache/wal/colors.sh" ]; then
  # shellcheck disable=SC1090
  source "${HOME}/.cache/wal/colors.sh"
fi

# Try to notify/restart small things that commonly use colors.
# You can uncomment the lines you need / adapt to your setup:
# restart dunst (if you want it to reload colors)
# pkill dunst || true
# dunst &>/dev/null &

# reload i3 so bars/themes pick new colors (restart will keep layout)
# i3-msg restart >/dev/null 2>&1 || true

# Example: reload polybar (if you use it)
# pkill -SIGUSR1 polybar || true

echo "pywal applied. Done."
