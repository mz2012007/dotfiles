#!/bin/sh
sudo xbps-install -S # > /dev/null 2>&1
xbps-install -un | wc -l

