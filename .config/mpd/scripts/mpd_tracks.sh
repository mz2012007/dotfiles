#!/usr/bin/env bash

TRACK=$(mpc listall | rofi -dmenu -i -p "🎵 Play Track" -show drun -show-icons -theme /home/mz/.config/rofi/rofi.mz/themes/spotlight-dark.rasi)

if [ -n "$TRACK" ]; then
  mpc clear
  mpc add "$TRACK"
  mpc play
fi
