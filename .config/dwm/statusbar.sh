#!/usr/bin/env bash

while :; do
  lang=$(xkb-switch -p)

  mem=$(free -m | awk '/Mem:/ {printf "%d/%dMB", $3, $2}')
  date_time=$(date +"%I:%M %p")

  xsetroot -name "   | RAM:$mem | KB:$lang | $date_time         "

  sleep 1
done
