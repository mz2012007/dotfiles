#!/usr/bin/env bash

#exec > >(tee -i $HOME/.config/dwm/dwm/autostart.log)

dwmblocks &
xxkb &
aplay /usr/share/sounds/alsa/Front_Center.wav &
$HOME/dotfiles/.config/dwm/dwmblocks/scripts/mpdup.sh &
