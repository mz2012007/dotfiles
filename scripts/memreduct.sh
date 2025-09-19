#!/usr/bin/env bash

sudo sync
echo 3 | sudo tee /proc/sys/vm/drop_caches

notify-send -i system-run " ✅ ram has cleaned "
