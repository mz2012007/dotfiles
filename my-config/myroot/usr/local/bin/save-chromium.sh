#!/usr/bin/bash
rsync -a --delete /dev/shm/chromium-profile/ ~/.config/chromium.bak/
rsync -a --delete /dev/shm/chromium-cashe/ ~/.config/chromium-cashe.bak/

