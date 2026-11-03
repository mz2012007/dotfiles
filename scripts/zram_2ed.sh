#!/bin/bash

set -Eeuo pipefail

readonly ZRAM_SIZE="14G"
readonly ZRAM_ALGORITHM="zstd"
readonly SWAP_PRIORITY="100"

if [[ $EUID -ne 0 ]]; then
  printf 'Error: Run this script as root.\n' >&2
  exit 1
fi

if ! command -v zramctl >/dev/null 2>&1; then
  printf 'Error: zramctl is not installed.\n' >&2
  exit 1
fi

if swapon --noheadings --show=NAME | grep -q '^/dev/zram'; then
  printf 'Error: A ZRAM swap device is already active.\n' >&2
  printf 'Inspect it with: zramctl\n' >&2
  exit 1
fi

modprobe zram

if ! grep -qw "$ZRAM_ALGORITHM" /sys/block/zram0/comp_algorithm 2>/dev/null; then
  printf 'Error: zstd is not available for zram0.\n' >&2
  exit 1
fi

device=$(zramctl --find --size "$ZRAM_SIZE" --algorithm "$ZRAM_ALGORITHM")

if [[ -z "$device" ]]; then
  printf 'Error: Failed to allocate a ZRAM device.\n' >&2
  exit 1
fi

cleanup() {
  swapoff "$device" 2>/dev/null || true
  zramctl --reset "$device" 2>/dev/null || true
}

trap cleanup ERR

mkswap "$device"
swapon --priority "$SWAP_PRIORITY" "$device"

trap - ERR

printf '\nZRAM initialized successfully.\n'
zramctl "$device"
swapon --show
