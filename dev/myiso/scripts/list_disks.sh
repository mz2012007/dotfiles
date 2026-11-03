#!/usr/bin/env bash
set -Eeuo pipefail

# List available block devices (excluding loop devices)
lsblk -d -o NAME,SIZE,MODEL -n | awk '$3 != "" {print "/dev/" $1, $2, $3}'
