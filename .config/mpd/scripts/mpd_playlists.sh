#!/usr/bin/env bash

PLAYLIST=$(mpc lsplaylists | rofi -dmenu -i -p "📂 Play Playlist" -show drun -show-icons -theme /home/mz/.config/rofi/rofi.mz/themes/spotlight-dark.rasi)

if [ -n "$PLAYLIST" ]; then
  mpc clear
  mpc load "$PLAYLIST"
  mpc play
fi
