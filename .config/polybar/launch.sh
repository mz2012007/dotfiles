#!/bin/bash

# إيقاف أي شريط polybar سابق
#killall -q polybar

# الانتظار حتى يُقتل السابق
#while pgrep -u $UID -x polybar >/dev/null; do sleep 1; done

# تشغيل polybar
#polybar i3 &

pkill -x polybar

sleep 1

polybar i3 &
