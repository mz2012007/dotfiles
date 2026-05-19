#!/usr/bin/env bash

base=(
  void-repo-nonfree
  void-docs-browse
  curl
  wget
  rsync
  unzip
  htop
  btop
  pkg-config
  fd
  bash-completion
  dialog
  gcc
  util-linux
  python3-pipx
  gvfs-mtp
  mtpfs
  jmtpfs
  chrony
  fcron
  ncdu2
  plymouth
  acpi
  mpd
  mpc
  ncmpcpp
  bat
  make
  rsyslog
  p7zip
  bsdtar
  openssh
  tree
  git
  ccze
  setxkbmap
)

system_performance=(
  preload
  earlyoom
  zramen
  fake-hwclock
  cpupower
  elogind
  fzf
  trash-cli
  eza
  zoxide
  cmatrix
  fastfetch
  fish-shell
  babelfish
  xprop
  tmux
  xclip
  xkb-switch
  neovim
  nano
  ripgrep
  ranger
  starship
  xorg-server-xephyr
  pavucontrol
  lm_sensors
  calcurse
  eyeD3
  mtools
  just
)

dwm=(
  libxcb
  libxcb-devel
  pango
  pango-xft
  pango-devel
  xcb-util
  xcb-util-devel
  xcb-util-wm
  xcb-util-wm-devel
  libXinerama-devel
)

intel_drivers=(
  acpica-utils
  xf86-video-intel
  intel-video-accel
  mesa-intel-dri

)

gui_base=(
  xfce-polkit
  mpv
  neovim-qt
)

network_services=(
  NetworkManager
  network-manager-applet
  lsof
  dnsmasq
)

sound_pulseaudio=(
  pulseaudio
)

sound_pipewire=(
  pipewire
  wireplumber
)

blutouth=(
  bluez
  blueman
)

privacy=(
  ufw
  gufw
)

lightdm=(
  lightdm
  lightdm-gtk-greeter-settings
)

base_apps=(
  rofi
  volumeicon
  dunst
  alacritty
  zen-browser
  feh
  fsearch
  gparted
  stow
  gnome-calculator
  xclip
  xclipboard
  conky
  brightnessctl
  flameshot
  picom
  mousepad
  mtpaint
  dolphin
)

desktop_gui_i3=(
  i3-gaps
  i3lock-color
  autotiling
  polybar
)

fonts_themes=(
  xorg-fonts
  noto-fonts-emoji
  noto-fonts-ttf
  noto-fonts-ttf-extra
  noto-fonts-ttf-variable
  adwaita-plus
  adwaita-qt
  adwaita-qt6
  lxappearance
)

xorg_drivers=(
  xorg-minimal
  xf86-input-libinput
  mesa-demos
  xorgproto
)

boot_grub=(
  grub
  grub-customizer
  grub-x86_64-efi
)

xmonad_requirements=(
  ncurses-libtinfo-libs
  ncurses-libtinfo-devel
  libX11-devel
  libXft-devel
  libXinerama-devel
  libXrandr-devel
  libXScrnSaver-devel
  pkg-config
  ghc
  cabal-install
)

docker=(
  docker
  docker-cli
  docker-compose
)
