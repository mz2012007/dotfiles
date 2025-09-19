#!/bin/sh
xxkb &
#~/.dwm/statusbar.sh &
setxkbmap -layout us,ara -option grp:alt_shift_toggle &
#ionice -c2 -n7 picom --config ~/.config/picom/picom.conf &
dunst &
nm-applet &
ionice -c2 -n7 feh --bg-scale ~/Pictures/1.jpg &
~/.config/conky/launc.sh &
polybar &

