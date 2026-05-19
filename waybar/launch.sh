#!/usr/bin/env bash

# Kill existing waybar instances
pkill waybar

# Wait until the processes have been shut down
while pgrep -x waybar >/dev/null; do
  sleep 0.1
done

# Launch waybar
exec waybar &
