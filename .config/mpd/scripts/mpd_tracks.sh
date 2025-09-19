#!/usr/bin/env bash

# يعرض كل الأغاني ويشغل اللي تختاره
TRACK=$(mpc listall | rofi -dmenu -i -p "🎵 Play Track")

if [ -n "$TRACK" ]; then
  mpc clear
  mpc add "$TRACK"
  mpc play
fi
