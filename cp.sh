#!/usr/bin/env bash

sudo rsync -aAXv /etc/lightdm/lightdm-gtk-greeter.conf ~/dotfiles/my-config/myroot/etc/lightdm/
sudo rsync -aAXv /boot/grub/themes/ ~/dotfiles/my-config/myroot/boot/grub/themes/
#sudo cp -r /etc/default/grub ~/dotfiles/my-config/myroot/etc/default/
sudo rsync -aAXv /etc/resolv.conf ~/dotfiles/my-config/myroot/etc/
