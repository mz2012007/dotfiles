#!/usr/bin/env bash

sudo -v

while true; do
  sudo -v
  sleep 30
done &
SUDO_REFRESH_PID=$!

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
sudo cp -r $HOME/dotfiles/my-config/myroot/etc/resolv.conf /etc/resolv.conf || {
  echo "❌ reslov.conf clone failed"
}

# update time
sudo chronyc makestep

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

sudo -v

# remove old dirs in home
find "$HOME" -mindepth 1 -maxdepth 1 ! -name "dotfiles" -exec rm -rf {} +

# install using pipx
pipx install pywal16 || {
  echo "❌ install pywal16 has failed"
}

# stow
stow .
echo "✅ stow completed"

# user directories
home_dirs=(
  "$HOME/Desktop"
  "$HOME/Downloads"
  "$HOME/.config/tmux/plugins"
  "$HOME/Music/playlists/"
)

for d in "${home_dirs[@]}"; do
  mkdir -p "$d"
  echo "✅ Created (user) $d"
done

# root directories
root_dirs=(
  "/etc/modprobe.d"
  "/etc/X11/xorg.conf.d"
  "/etc/xdg/autostart"
  "/etc/polkit-1"
  "/etc/lightdm"
  "/etc/polkit-1/rules.d"
  "/boot/grub/themes/"
  "/usr/share/fonts"
  "/usr/share/themes"
  "/mnt/srv/docker/comp/"
  "/mnt/srv/docker/cont/n8n/data"
  "/mnt/srv/docker/cont/nginx"
  "/mnt/srv/docker/cont/heimdall/config"
  "/mnt/srv/docker/cont/syncthing/config"
  "/mnt/srv/data"
  "/mnt/srv/docker/cont/npm/data"
  "/mnt/srv/docker/cont/npm/letsencrypt"
  "/mnt/srv/docker/cont/pyload"
  "/mnt/srv/downloads/pyload"
  "/mnt/srv/docker/cont/jellyfin/config"
  "/mnt/srv/data/media"
  "/mnt/srv/docker/cont/nextcloud/db"
  "/mnt/srv/docker/cont/nextcloud/db-backup"
  "/mnt/srv/docker/cont/nextcloud/html"
  "/mnt/srv/data/media"
  "/mnt/srv/docker/cont/nginx"
  "/var/run/docker.sock"
  "/mnt/srv/docker/cont/portainer"
)

for d in "${root_dirs[@]}"; do
  sudo mkdir -p "$d"
  echo "✅ Created (root) $d"
done

# copy configuration files safely
sudo rsync -aAXv $HOME/dotfiles/my-config/myroot/etc/modprobe.d/blacklist.conf /etc/modprobe.d/
sudo rsync -aAXv $HOME/dotfiles/my-config/myroot/etc/X11/xorg.conf.d/* /etc/X11/xorg.conf.d/
sudo rsync -aAXv $HOME/dotfiles/my-config/myroot/etc/xdg/autostart/nm-applet.desktop /etc/xdg/autostart/
sudo rsync -aAXv $HOME/dotfiles/my-config/myroot/etc/polkit-1/rules.d/my-safe.rules /etc/polkit-1/rules.d/
sudo rsync -aAXv $HOME/dotfiles/my-config/myroot/etc/lightdm/lightdm.conf /etc/lightdm/
sudo rsync -aAXv $HOME/dotfiles/my-config/myroot/etc/lightdm/lightdm-gtk-greeter.conf /etc/lightdm/
sudo rsync -aAXv $HOME/dotfiles/my-config/myroot/usr/share/fonts/* /usr/share/fonts/
sudo rsync -aAXv $HOME/dotfiles/my-config/myroot/myhome/.config/tmux/tmux.conf ~/.config/tmux/
sudo rsync -aAXv $HOME/dotfiles/my-config/myroot/myhome/.config/tmux/tmux.conf.pack2 ~/.config/tmux/
sudo rsync -aAXv $HOME/dotfiles/.config/fish/* /root/.config/
sudo rsync -aAXv $HOME/dotfiles/fcrorntab/* /var/spool/fcron/
sudo rsync -aAXv $HOME/dotfiles/my-config/myroot/usr/share/themes/* /usr/share/themes/
sudo rsync -aAXv /etc/multitail.conf.new /etc/multitail.conf
sudo rsync -aAXv $HOME/dotfiles/my-config/myroot/etc/default/grub /etc/default/grub
sudo rsync -aAXv $HOME/dotfiles/my-config/myroot/boot/grub/themes/* /boot/grub/themes/
sudo rsync -aAXv $HOME/dotfiles/my-config/docker-compose.yml /mnt/srv/docker/comp/docker-compose.yml
sudo rsync -aAXv $HOME/dotfiles/my-config/myroot/etc/hosts /etc/hosts
sudo rsync -aAXv $HOME/dotfiles/my-config/myroot/etc/hostname /etc/hostname

# user touch
touch_files=(
  "$HOME/mpd/mpd.db"
  "$HOME/mpd/mpd.pid"
  "$HOME/mpd/mpdstate"
  "$HOME/mpd/mpd.log"
)

for d in "${touch_files[@]}"; do
  touch "$d"
  echo "✅ Created file $d"
done

# priviligios
sudo chown -R $USER:$USER $HOME
sudo chown -R $USER:$USER /var/run/docker.sock

sudo chmod 755 $HOME

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
  dbus
  earlyoom
  chronyd
  fake-hwclock
  lightdm
  preload
  zramen
  udevd
  elogind
  polkitd
  fcron
  rsyslogd
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

git clone https://github.com/tmux-plugins/tpm $HOME/.config/tmux/plugins/tpm || {
  echo "❌ TPM clone failed"
}

# install script for mpv
cd $HOME/.config
git clone --depth 1 --filter=blob:none --sparse https://github.com/mz2012007/mpv.git
cd $HOME/.config/mpv
git sparse-checkout set scripts || {
  echo "❌ MPV clone failed"
}
cd $HOME/dotfiles

# time
sudo chronyc makestep
sudo hwclock --systohc
echo "Time has updated"

# install my pkgs
cd $HOME/dotfiles/pkg-xbps/
sudo xbps-rindex -a *.xbps
sudo xbps-install --repository=$PWD ccze

# fonts
fc-cache -fv
echo "Fonts has updated"

# groups
services=(
  adm
  dialout
  lightdm
  plugdev
  storage
  wheel
  audio
  _pipewire
  disk
  lp
  polkitd
  sys
  xbuilder
  bin
  dnsmasq
  mail
  pulse
  tape
  _dhcpcd
  bluetooth
  fcron
  mpd
  pulse-access
  tty
  _uuidd
  cdrom
  floppy
  root
  usbmon
  chrony
  input
  network
  rtkit
  users
  daemon
  kmem
  nogroup
  scanner
  utmp
  dbus
  kvm
  optical
  sgx
  video
)

for svc in "${services[@]}"; do
  sudo usermod -aG "$svc" "$USER"
  echo "✅ Added $svc"
done

# cashe

#echo "vm.swappiness=10
#vm.vfs_cache_pressure=50
#vm.dirty_ratio=10
#vm.dirty_background_ratio=5
#vm.min_free_kbytes=65536
#vm.dirty_writeback_centisecs=1500
#vm.dirty_expire_centisecs=3000
#vm.page-cluster=0" >>/etc/sysctl.conf

# update grub
sudo update-grub || {
  echo "❌ update grub has failed"
}

# finish
echo "====================================="
echo "🎉 System setup complete!"
echo "📂 Logs saved to setup.log"
echo "🔄 Reboot to apply configs"
echo "====================================="

read -rp "🔄 Reboot now? [y/N]: " answer
[[ $answer == [Yy]* ]] && sudo reboot
