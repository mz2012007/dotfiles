#!/usr/bin/env bash

# Module showing CPU load as a changing bars.
# Just like in polybar.
# Each bar represents amount of load on one core since
# last run.

GREEN="#50fa7b"
YELLOW="#f1fa8c"
ORANGE="#ffb86c"
RED="#ff5555"
RESET="#f8f8f2"

# Cache in tmpfs to improve speed and reduce SSD load
cache=/tmp/cpubarscache

case $BLOCK_BUTTON in
1) kill -RTMIN+7 $(pidof dwmblocks) ;;
2) setsid -f "$TERMINAL" -e htop ;;
3) notify-send "🪨 CPU load module" "Each bar represents
one CPU core" ;;
6) setsid -f "$TERMINAL" -e "$EDITOR" "$0" ;;
esac

# id total idle
stats=$(awk '/cpu[0-9]+/ {printf "%d %d %d\n", substr($1,4), ($2 + $3 + $4 + $5), $5 }' /proc/stat)
[ ! -f $cache ] && echo "$stats" >"$cache"
old=$(cat "$cache")
printf "|🪨 "
echo "$stats" | while read -r row; do
  id=${row%% *}
  rest=${row#* }
  total=${rest%% *}
  idle=${rest##* }

  val="$(echo "$old" | awk '{if ($1 == id)
      printf "%d\n", (1 - (idle - $3)  / (total - $2))*100 /12.5}' \
    id="$id" total="$total" idle="$idle")"

  case "$val" in
  0 | 1 | 2) col="$GREEN" ;;
  3 | 4) col="$YELLOW" ;;
  5) col="$ORANGE" ;;
  6 | 7 | 8) col="$RED" ;;
  *) col="$RESET" ;;
  esac

  case "$val" in
  0) bar="▁" ;;
  1) bar="▂" ;;
  2) bar="▃" ;;
  3) bar="▄" ;;
  4) bar="▅" ;;
  5) bar="▆" ;;
  6) bar="▇" ;;
  7 | 8) bar="█" ;;
  esac
  printf "^c%s^%s" "$col" "$bar"

done
printf "\\n"
echo "$stats" >"$cache"
