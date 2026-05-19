#!/usr/bin/env bash

TMPFILE="/tmp/.network_click_time"

NOW=$(date +%s%3N)
LAST=$(cat $TMPFILE 2>/dev/null || echo 0)

DIFF=$((NOW - LAST))

echo $NOW > $TMPFILE

if [ $DIFF -lt 500 ]; then
    alacritty -e nmtui
fi

