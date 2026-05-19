#!/usr/bin/env bash
#sudo sync

if sync && echo 3 | pkexec tee /proc/sys/vm/drop_caches >/dev/null; then
  notify-send -i system-run "✅ RAM cache cleaned successfully"
else
  notify-send -i dialog-error "❌ Failed to clean RAM cache"
fi
