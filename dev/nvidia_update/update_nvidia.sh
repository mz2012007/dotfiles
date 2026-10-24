#!/bin/bash

set -euo pipefail

NVIDIA_DIR="$HOME/Downloads/nvidia"
KVER="$(uname -r)"
MODDIR="/lib/modules/$KVER/kernel/drivers/video"

log() {
  printf '\n[%s] %s\n' "$(date '+%H:%M:%S')" "$*"
}

die() {
  echo "[ERROR] $*" >&2
  exit 1
}

version_gt() {
  [ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | tail -n1)" = "$1" ] &&
    [ "$1" != "$2" ]
}

cd "$NVIDIA_DIR"

log "Detecting NVIDIA .run packages"

mapfile -t RUNS < <(
  find "$NVIDIA_DIR" -maxdepth 1 -type f \
    -name 'NVIDIA-Linux-x86_64-*.run' \
    -printf '%f\n' |
    sort -V
)

[ "${#RUNS[@]}" -gt 0 ] || die "No NVIDIA .run package found"

LATEST="${RUNS[-1]}"

NEW_VERSION="$(
  sed -nE 's/^NVIDIA-Linux-x86_64-([0-9.]+)\.run$/\1/p' <<<"$LATEST"
)"

[ -n "$NEW_VERSION" ] || die "Could not determine NVIDIA version"

CURRENT_VERSION=""

if modinfo -F version nvidia >/dev/null 2>&1; then
  CURRENT_VERSION="$(modinfo -F version nvidia)"
elif [ -f /sys/module/nvidia/version ]; then
  CURRENT_VERSION="$(cat /sys/module/nvidia/version)"
fi

echo
echo "========================================"
echo " NVIDIA DRIVER UPDATE"
echo "========================================"
echo "Kernel : $KVER"
echo "Current: ${CURRENT_VERSION:-not installed}"
echo "Latest : $NEW_VERSION"
echo "Package: $LATEST"
echo "========================================"

if [ -n "$CURRENT_VERSION" ] &&
  ! version_gt "$NEW_VERSION" "$CURRENT_VERSION"; then
  echo
  echo "No newer NVIDIA driver found."
  exit 0
fi

echo
read -r -p "Install NVIDIA $NEW_VERSION? [y/N] " ANSWER

case "$ANSWER" in
y | Y | yes | YES)
  ;;
*)
  echo "Cancelled."
  exit 0
  ;;
esac

EXTRACT_DIR="$NVIDIA_DIR/NVIDIA-Linux-x86_64-$NEW_VERSION"

log "Removing previous extraction"

rm -rf "$EXTRACT_DIR"

log "Extracting NVIDIA package"

sh "$LATEST" --extract-only

[ -d "$EXTRACT_DIR" ] || die "Extraction failed"

log "Checking kernel-open source"

[ -d "$EXTRACT_DIR/kernel-open" ] ||
  die "kernel-open directory not found"

cd "$EXTRACT_DIR/kernel-open"

log "Creating source backup"

cp nvidia/nv-clk.c nvidia/nv-clk.c.orig

log "Applying nv-clk.c patch"

python3 - <<'PY'
from pathlib import Path

path = Path("nvidia/nv-clk.c")
source = path.read_text()

old = """#include <soc/tegra/bpmp-abi.h>
#include <soc/tegra/bpmp.h>"""

new = """#if IS_ENABLED(CONFIG_TEGRA_BPMP)
#include <soc/tegra/bpmp-abi.h>
#include <soc/tegra/bpmp.h>
#endif // IS_ENABLED(CONFIG_TEGRA_BPMP)"""

if source.count(old) != 1:
    raise SystemExit(
        "Expected Tegra BPMP include block not found exactly once"
    )

path.write_text(source.replace(old, new))

print("Patch applied successfully")
PY

log "Showing patch"

diff -u nvidia/nv-clk.c.orig nvidia/nv-clk.c || true

log "Building NVIDIA open kernel modules"

make -j"$(nproc)" \
  SYSSRC="/lib/modules/$KVER/build" \
  SYSOUT="/lib/modules/$KVER/build"

log "Checking generated modules"

for module in \
  nvidia \
  nvidia-uvm \
  nvidia-modeset \
  nvidia-drm \
  nvidia-peermem; do
  [ -f "$module.ko" ] ||
    die "Build did not produce $module.ko"

  printf "%-20s " "$module"
  modinfo -F version "./$module.ko"
done

log "Kernel module build succeeded"

echo
echo "========================================"
echo " BUILD SUCCESSFUL"
echo "========================================"
echo "The old driver will now be removed."
echo "========================================"
echo

read -r -p "Continue installation? [Y/n] " ANSWER

case "$ANSWER" in
n | N | no | NO)
  echo "Installation cancelled."
  exit 0
  ;;
esac

log "Stopping NVIDIA modules"

sudo modprobe -r nvidia_drm 2>/dev/null || true
sudo modprobe -r nvidia_modeset 2>/dev/null || true
sudo modprobe -r nvidia_uvm 2>/dev/null || true
sudo modprobe -r nvidia 2>/dev/null || true

log "Removing old NVIDIA kernel modules"

for module in \
  nvidia \
  nvidia-uvm \
  nvidia-modeset \
  nvidia-drm \
  nvidia-peermem; do
  rm -f \
    "$MODDIR/$module.ko" \
    "$MODDIR/$module.ko.zst"
done

log "Installing new NVIDIA kernel modules"

for module in \
  nvidia \
  nvidia-uvm \
  nvidia-modeset \
  nvidia-drm \
  nvidia-peermem; do
  sudo install -D -m 0644 \
    "$module.ko" \
    "$MODDIR/$module.ko"
done

log "Updating module dependencies"

sudo depmod -a "$KVER"

log "Installing NVIDIA userspace"

cd "$EXTRACT_DIR"

sudo ./nvidia-installer \
  --no-kernel-modules \
  --no-questions

log "Rebuilding initramfs"

sudo dracut --force \
  "/boot/initramfs-$KVER.img" \
  "$KVER"

log "Final module check"

echo
echo "========================================"
echo " NVIDIA MODULES"
echo "========================================"

for module in \
  nvidia \
  nvidia-uvm \
  nvidia-modeset \
  nvidia-drm \
  nvidia-peermem; do
  printf "%-20s " "$module"
  modinfo -F version "$module"
done

echo
echo "========================================"
echo " NVIDIA UPDATE COMPLETE"
echo "========================================"
echo "Version: $NEW_VERSION"
echo "Kernel : $KVER"
echo "========================================"

echo
echo "Reboot is recommended."
