#!/usr/bin/env bash

RED="#ff5555"
YELLOW="#f1fa8c"
GREEN="#50fa7b"
FG="#f8f8f2"
BG="#1e1e2e"
SLASH_COL="#bd93f9"

case $BLOCK_BUTTON in
2) setsid -f "$TERMINAL" -e htop ;;
3) notify-send "🧠 Memory module" "\- Shows Memory Used/Total.
- Click to show memory hogs.
- Middle click to open htop." ;;
6) setsid -f "$TERMINAL" -e "$EDITOR" "$0" ;;
esac

read used total <<EOF
$(free --mebi | awk 'NR==2 {print $3, $2}')
EOF

used_p=$((used * 100 / total))

if [ "$used_p" -ge 80 ]; then
  col="$RED"
elif [ "$used_p" -ge 40 ]; then
  col="$YELLOW"
else
  col="$GREEN"
fi

used_g=$(awk "BEGIN {printf \"%.2f\", $used/1024}")
total_g=$(awk "BEGIN {printf \"%.2f\", $total/1024}")

printf "^b%s^|^c%s^🧠 %sGB^c%s^%sGiB ^c%s^%s%%|" \
  "$BG" "$col" "$used_g" "$SLASH_COL" "/$total_g" "$col" "$used_p"
