#!/bin/sh

while true; do
    # اللغة
    lang=$(xkb-switch -p)

    # استهلاك المعالج
    cpu=$(grep 'cpu ' /proc/stat | awk '{usage=($2+$4)*100/($2+$4+$5)} END {printf "%.1f%%", usage}')

    # استهلاك الرام
    mem=$(free -m | awk '/Mem:/ {printf "%d/%dMB", $3, $2}')

    # الوقت مع AM/PM
    date_time=$(date +"%I:%M %p")

    # تحديث البار
    xsetroot -name "CPU:$cpu | RAM:$mem | KB:$lang | $date_time"

    sleep 1
done

