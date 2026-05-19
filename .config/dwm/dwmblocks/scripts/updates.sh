#!/usr/bin/env bash

TERMINAL="alacritty"
EDITOR="nvim"

xbps-install -S &>/dev/null

updates=$(xbps-install -un | wc -l)

if [ "$updates" -gt 0 ]; then
  printf "^c#ffffff^^b#5f0000^  %s ^b#000000^^c#ffffff^" "$updates"
else
  printf "^c#888888^  0 ^c#ffffff^"
fi

case $BLOCK_BUTTON in
6) setsid -f "$TERMINAL" -e "$EDITOR" "$0" ;;
esac
