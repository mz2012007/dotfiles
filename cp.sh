#!/usr/bin/env bash

sudo rsync -aAXv /etc/lightdm/lightdm-gtk-greeter.conf ~/dotfiles/my-config/myroot/etc/lightdm/
sudo rsync -aAXv /etc/polkit-1/rules.d/my-safe.rules ~/dotfiles/my-config/myroot/etc/polkit-1/rules.d/my-safe.rules
sudo rsync -aAXv /boot/grub/themes/* ~/dotfiles/my-config/myroot/boot/grub/themes/
sudo rsync -aAXv /etc/default/grub ~/dotfiles/my-config/myroot/etc/default/grub
sudo rsync -aAXv /etc/resolv.conf ~/dotfiles/my-config/myroot/etc/
sudo rsync -aAXv /var/spool/fcron/ ~/dotfiles/fcrorntab/
sudo rsync -aAXv /etc/hostname ~/dotfiles/my-config/myroot/etc/hosts
sudo rsync -aAXv /etc/hosts ~/dotfiles/my-config/myroot/etc/hostname

sudo chown -R mz:mz $HOME
