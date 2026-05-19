#!/usr/bin/env bash

TERMINAL="alacritty"
EDITOR="nvim"

case $BLOCK_BUTTON in
1) ;;
3)
  notify-send "💡 Brightness module" "\- Shows current brightness level ☀️."
  ;;
4) brightnessctl set +10% && kill -RTMIN+6 $(pidof dwmblocks) ;;
5) brightnessctl set 10-% && kill -RTMIN+6 $(pidof dwmblocks) ;;
6)
  setsid -f "$TERMINAL" -e "$EDITOR" "$0"
  ;;
esac

# current brightness
curr_brightness=$(cat /sys/class/backlight/*/brightness)

# max_brightness
max_brightness=$(cat /sys/class/backlight/*/max_brightness)

# brightness percentage
brightness_per=$((100 * curr_brightness / max_brightness))

echo "💡 ${brightness_per}%"
