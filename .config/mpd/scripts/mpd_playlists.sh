#!/usr/bin/env bash

# يعرض كل البلاي ليست ويشغل اللي تختاره
PLAYLIST=$(mpc lsplaylists | rofi -dmenu -i -p "📂 Play Playlist")

if [ -n "$PLAYLIST" ]; then
  mpc clear
  mpc load "$PLAYLIST"
  mpc play
fi
