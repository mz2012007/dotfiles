#!/usr/bin/env bash

# ===== config =====
STEP=5
ICON=""
BG="#000000"
FG="#ffffff"
LOW="#50fa7b"
MID="#f1fa8c"
HIGH="#ff5555"
MUTED="#6272a4"
# ==================

get_sink() {
  pactl get-default-sink
}

get_vol() {
  pactl get-sink-volume "$(get_sink)" | awk '{print $5}' | tr -d '%'
}

is_muted() {
  pactl get-sink-mute "$(get_sink)" | awk '{print $2}'
}

case "$BLOCK_BUTTON" in
2) pavucontrol & ;;
4) pactl set-sink-volume "$(get_sink)" +"$STEP"% ;;
5) pactl set-sink-volume "$(get_sink)" -"$STEP"% ;;
1) pactl set-sink-mute "$(get_sink)" toggle ;;
6) setsid -f "$TERMINAL" -e "$EDITOR" "$0" ;;
esac

vol="$(get_vol)"
muted="$(is_muted)"

if [ "$muted" = "yes" ]; then
  col="$MUTED"
  text="MUTE"
else
  if ((vol >= 70)); then
    col="$HIGH"
  elif ((vol >= 30)); then
    col="$MID"
  else
    col="$LOW"
  fi
  text="${vol}%"
fi

printf "^b%s^^c%s^ %s  ^c%s^%s " \
  "$BG" "$col" "$ICON" "$FG" "$text"
