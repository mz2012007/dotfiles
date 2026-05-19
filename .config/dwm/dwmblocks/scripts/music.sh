#!/usr/bin/env bash

TERMINAL="alacritty"
EDITOR="nvim"

case $BLOCK_BUTTON in
1) mpc toggle ;; # right click, pause/unpause

3)
  notify-send "🎵 Music module" " Shows mpd song playing.
- ⏸ when paused.
- Left click toggle .
- Middle click opens ncmpcpp.
- Scroll changes track."
  ;; # right click, pause/unpause

2) setsid -f "$TERMINAL" -e ncmpcpp ;;

4) mpc prev ;; # scroll up, previous

5) mpc next ;; # scroll down, next

6) setsid -f "$TERMINAL" -e "$EDITOR" "$0" ;;

esac

status=$(mpc status | awk 'NR==2 {gsub(/\[|\]/,"",$1); print $1}')

repeat=$(mpc status | awk 'NR==3 {print $3}')
random=$(mpc status | awk 'NR==3 {print $5}')
single=$(mpc status | awk 'NR==3 {print $7}')
consume=$(mpc status | awk 'NR==3 {print $9}')

case "$status" in
playing) icon="⏵" ;;
paused) icon="⏸" ;;
stopped) icon="⏹" ;;
*) icon="?" ;;
esac

[ "$repeat" = "on" ] && icon+=" ⟳"
[ "$repeat" = "on" ] && [ "$single" = "on" ] && icon+=" ①" # repeatone
[ "$single" = "on" ] && [ "$repeat" != "on" ] && icon+=" ①"
[ "$consume" = "on" ] && icon+=" ✀ "
[ "$random" = "on" ] && icon+=" ⇄"

m=$icon

#printf "^c1E90FF^⏮ ^cFF4500^%s^c32CD32^⏭ " "$m"
printf "⏮ $m ⏭  "
