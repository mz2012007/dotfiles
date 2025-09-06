#!/usr/bin/env bash

sudo true

# more secure
#set -e

# logs
exec > >(tee -i setup.log)
exec 2>&1

# check it is void linux
if ! grep -q "Void" /etc/os-release; then
  echo "this is for void only"
  exit 1
fi

# stop if run as root
if [ "$EUID" -eq 0 ]; then
  echo "❌ Do not run this script as root!"
  exit 1
fi

# check sudo
if ! sudo -v; then
  echo "❌ sudo not available. Please configure sudo first."
  exit 1
fi

# starting welcome
echo "====================================="
echo "🚀 Starting Void Linux setup..."
echo "====================================="

# reslov.conf (dns)
sudo cp -r $HOME/dotfiles/my-config/myroot/etc/resolv.conf /etc/resolv.conf

# update system
echo "🔄 Updating system..."
sudo xbps-install -Syu

# install packages
if [ -f packages.txt ]; then
  echo "📦 install started"
  grep -vE '^\s*#|^\s*$' packages.txt | xargs sudo xbps-install -Sy
else
  echo "⚠️ cannot find packages.txt !"
fi

# remove old dirs in home
find "$HOME" -mindepth 1 -maxdepth 1 ! -name "dotfiles" -exec rm -rf {} +

# stow
stow .
echo "✅ stow completed"

# user directories
home_dirs=(
  "$HOME/Desktop"
  "$HOME/Music"
  "$HOME/Downloads"
  "$HOME/.config/tmux"
  "$HOME/.config/tmux/plugins"
)

for d in "${home_dirs[@]}"; do
  mkdir -p "$d"
  echo "✅ Created (user) $d"
done

# root directories
root_dirs=(
  "/etc/modprobe.d"
  "/etc/X11"
  "/etc/X11/xorg.conf.d"
  "/etc/xdg/autostart"
  "/etc/xdg/autostart"
  "/etc/polkit-1"
  "/etc/lightdm"
  "/etc/polkit-1/rules.d"
  "/usr/share/fonts"
)

for d in "${root_dirs[@]}"; do
  sudo mkdir -p "$d"
  echo "✅ Created (root) $d"
done

# copy configuration files safely
sudo cp -r $HOME/dotfiles/my-config/myroot/etc/modprobe.d/blacklist.conf /etc/modprobe.d/
sudo cp -r $HOME/dotfiles/my-config/myroot/etc/X11/xorg.conf.d/* /etc/X11/xorg.conf.d/
sudo cp -r $HOME/dotfiles/my-config/myroot/etc/xdg/autostart/nm-applet.desktop /etc/xdg/autostart/
sudo cp -r $HOME/dotfiles/my-config/myroot/etc/polkit-1/rules.d/my-safe.rules /etc/polkit-1/rules.d/
sudo cp -r $HOME/dotfiles/my-config/myroot/etc/lightdm/lightdm.conf /etc/lightdm/
sudo cp -r $HOME/dotfiles/my-config/myroot/etc/lightdm/lightdm-gtk-greeter.conf /etc/lightdm/
sudo cp -r $HOME/dotfiles/my-config/myroot/usr/share/fonts/* /usr/share/fonts/
sudo cp -r $HOME/dotfiles/my-config/myroot/myhome/.config/tmux/tmux.conf ~/.config/tmux/
sudo cp -r $HOME/dotfiles/my-config/myroot/myhome/.config/tmux/tmux.conf.pack2 ~/.config/tmux/
sudo cp -r $HOME/dotfiles/.config/fish/ /root/.config/

# priviligios
sudo chown -R $USER:$USER $HOME

sudo chmod u+s /usr/bin/poweroff
sudo chmod u+s /usr/sbin/poweroff

sudo chmod u+s /usr/bin/reboot
sudo chmod u+s /usr/sbin/reboot

sudo chmod u+s /usr/bin/sleep
sudo chmod u+s /usr/sbin/sleep

sudo chmod u+s /usr/bin/zzz
sudo chmod u+s /usr/sbin/zzz

# change schell
chsh -s /usr/bin/fish
sudo chsh -s /usr/bin/fish

# services
services=(
  NetworkManager
  agetty-tty1
  agetty-tty2
  chronyd
  dbus
  earlyoom
  fake-hwclock
  lightdm
  preload
  zramen
  udevd
  dhcpcd
  elogind
  polkitd
)
for svc in "${services[@]}"; do
  if [ -d "/etc/sv/$svc" ]; then
    sudo ln -sfn "/etc/sv/$svc" /var/service/
    echo "✅ Enabled (or fixed) $svc"
  else
    echo "❌ Service $svc not found in /etc/sv"
  fi
done

for current in /var/service/*; do
  svc_name=$(basename "$current")
  if [[ ! " ${services[*]} " =~ " ${svc_name} " ]]; then
    sudo rm -rf "/var/service/$svc_name"
    echo "🗑️ Removed service: $svc_name"
  else
    echo "ℹ️ Kept service: $svc_name"
  fi
done

# install Tpm for tmux and install plugins

git clone https://github.com/tmux-plugins/tpm $HOME/.config/tmux/plugins/tpm

echo "✅ Tmux configured"

# time
sudo chronyc makestep
sudo hwclock --systohc
echo "Time has updated"

# fonts
fc-cache -fv
echo "Fonts has updated"

# groups
services=(
  wheel
  audio
  video
  input
  network
  lightdm
  storage
  plugdev
  kvm
  bluetooth
  lp
  scanner
  pulse
  pulse-access
  _pipewire
  optical
  xbuilder
  polkitd
)

for svc in "${services[@]}"; do
  sudo usermod -aG "$svc" "$USER"
  echo "✅ Added $svc"
done

# finish
echo "====================================="
echo "🎉 System setup complete!"
echo "📂 Logs saved to setup.log"
echo "🔄 Reboot to apply configs"
echo "====================================="

read -rp "🔄 Reboot now? [y/N]: " answer
[[ $answer == [Yy]* ]] && sudo reboot
