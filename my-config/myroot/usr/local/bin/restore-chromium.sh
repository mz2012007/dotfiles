#!/usr/bin/bash
mkdir -p /dev/shm/chromium-profile
rsync -a ~/.config/chromium.bak/ /dev/shm/chromium-profile/
ln -s /dev/shm/chromium-profile ~/.config/chromium


mkdir -p /dev/shm/chromium-cashe
rsync -a ~/.config/chromium-cashe.bak/ /dev/shm/chromium-cashe/
ln -s /dev/shm/chromium-cashe ~/.cashe/chromium


