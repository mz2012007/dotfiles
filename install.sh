#!/usr/bin/env bash
# Void Linux setup script
# Author: MohamedZaki automated review -> cleaned version for mz2012007/dotfiles

# source
source $HOME/dotfiles/packages.sh

# variables

# more secure
set -euo pipefail
IFS=$'\n\t'

LOGFILE="$HOME/setup.log"
DOTFILES="$HOME/dotfiles"
PACKAGES_SH="$HOME/dotfiles/packages.sh"

SUDO_REFRESH_PID=""

# colors
if [[ -t 1 ]]; then
  RED="\033[31m"
  GREEN="\033[32m"
  YELLOW="\033[33m"
  BLUE="\033[34m"
  RESET="\033[0m"
else
  RED="" GREEN="" YELLOW="" BLUE="" RESET=""
fi

# Helpers ----------------------------------------------------------
# safe_chmod
SAFE_CHMOD_SUID() {
  local path="$1"
  if [[ -e "$path" ]]; then
    sudo chmod u+s "$path" || error "chmod u+s failed on $path"
  else
    warn "file not found for chmod: $path"
  fi
}

# printf
info() { echo -e "${BLUE}ℹ️  $*${RESET}"; }
warn() { echo -e "${YELLOW}⚠️  $*${RESET}"; }
success() { echo -e "${GREEN}✅ $*${RESET}"; }
error() {
  echo -e "${RED}❌ $*${RESET}"
}

# REQUIRE_CMD
REQUIRE_CMD() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "❌ Required command not found: $cmd"
    exit 1
  fi
}

# ------------------------------------------------------------------

# sudo
SUDO_PRIV() {
  REQUIRE_CMD sudo
  sudo -v
  (
    while true; do
      sudo -v
      sleep 30
    done
  ) &
  SUDO_REFRESH_PID=$!
}

# cleanup
CLEANUP() {
  if [[ -n "${SUDO_REFRESH_PID:-}" ]]; then
    kill "${SUDO_REFRESH_PID}" 2>/dev/null || true
  fi
}

# logs
LOGS() {
  local mydate=$(date "+%Y_%b_%d-(%a)-%I:%M%p")
  mkdir -p "$(dirname "$LOGFILE")"
  exec > >(tee -a "$LOGFILE.$mydate") 2>&1
  echo "Log started at $(date "+%Y %b %d (%a) %I:%M%p")"
}

# Basic environment checks --------------------------------------------------
CHECK() {
  # check distribution
  if ! grep -q "Void" /etc/os-release; then
    error "This script is intended for Void Linux only."
    exit 1
  fi

  # don't run as root
  if [[ "${EUID:-0}" -eq 0 ]]; then
    error "Do not run this script as root."
    exit 1
  fi

  # check required commands early
  for cmd in xbps-install xbps-rindex rsync git stow pipx fzf chronyc hwclock plymouth-set-default-theme grub-mkconfig; do
    # fzf might be optional until later; only check presence of packages.sh and repo here
    true
  done

  # check repo presence
  if [[ ! -d "$DOTFILES" ]]; then
    error "Dorfiles dir not found: $DOTFILES"
    #    exit 1
  fi

  # optional packages.sh: warn if missing but keep going
  if [[ ! -f "$PACKAGES_SH" ]]; then
    warn "packages.sh not found at $PACKAGES_SH. Package groups functions will fail if invoked."
  else
    # shellcheck source=/dev/null
    # shellcheck disable=SC1090
    source "$PACKAGES_SH"
  fi

  # check sudo
  if ! sudo -v; then
    error "sudo not available. Please configure sudo first."
    exit 1
  fi
}

# repo
REPO() {
  info "Add zen-browser Repo .."
  sudo sh -c "echo 'repository=https://github.com/sofijacom/void-package/releases/latest/download/' > /etc/xbps.d/sofijacom-void-repository.conf" || error "Add zen-browser Repo"
  success "Added zen-browser Repo .."

  info "Add my-repo Repo .."
  sudo sh -c "echo 'repository=https://raw.githubusercontent.com/mz2012007/void-xbps/refs/heads/main/x86_64' > /etc/xbps.d/my-repo.conf"
  success "Added my-repo Repo .."

}

SELECT_FUNCTIONS_FZF() {
  # List of all setup functions
  local all_functions=(
    CHECK WELCOME DNS LOCALTIME TIME UPDATE_SYSTEM REPO
    SELECT_PACKAGES_FZF MV_HOME PIPX_APP MK_USER_DIRS MK_ROOT_DIRS
    STOW RSYNC MK_FILES PRIVILEGES DWM SHELL SERVICES TMUX MPV MY_PKGS
    FONTS GROUPS CACHE PRIVACY PLYMOUTH GRUB FINISH
  )

  # fzf interactive selection
  local selected
  selected=$(printf "%s\n" "${all_functions[@]}" | fzf --multi --reverse --prompt="Select functions to run > ") || return 1

  [[ -z $selected ]] && {
    warn "No functions selected."
    return 1
  }

  # convert selection into EXEC_PLAN array
  EXEC_PLAN=()
  while IFS= read -r fn; do
    EXEC_PLAN+=("$fn")
  done <<<"$selected"

}

RUN_SETUP() {
  REQUIRE_CMD fzf

  # profiles
  profiles=("old_lab" "during_work" "custom")

  profile=$(printf "%s\n" "${profiles[@]}" | fzf --prompt="Select setup profile > ") || {
    echo "No profile selected. Abort."
    return 1
  }

  EXEC_PLAN=()

  case "$profile" in
  old_lab)
    EXEC_PLAN=(CHECK WELCOME DNS LOCALTIME TIME UPDATE_SYSTEM REPO SELECT_PACKAGES_FZF MV_HOME PIPX_APP STOW MK_USER_DIRS MK_ROOT_DIRS RSYNC MK_FILES PRIVILEGES DWM SHELL SERVICES TMUX MPV MY_PKGS FONTS GROUPS CACHE PRIVACY GRUB FINISH)
    ;;
  during_work)
    EXEC_PLAN=(CHECK WELCOME LOCALTIME TIME SELECT_PACKAGES_FZF UPDATE_SYSTEM PRIVILEGES FINISH)
    ;;
  custom)
    # interactive fzf selection of functions
    SELECT_FUNCTIONS_FZF || return 1
    ;;
  *)
    echo "Unknown profile. Abort."
    return 1
    ;;
  esac

  echo
  echo "Execution plan:"
  for i in "${!EXEC_PLAN[@]}"; do
    printf "%2d. %s\n" "$((i + 1))" "${EXEC_PLAN[$i]}"
  done

  echo
  read -rp "Start execution of all steps? (y/N): " confirm
  [[ "$confirm" =~ ^[Yy]$ ]] || {
    warn "Execution aborted."
    return 1
  }

  # Run all functions without asking individually
  for fn in "${EXEC_PLAN[@]}"; do
    if declare -f "$fn" >/dev/null 2>&1; then
      echo -e "\n===== Running ${BLUE}$fn${RESET} ====="
      "$fn" && echo -e "${GREEN}✔ $fn completed${RESET}" || echo -e "${RED}✖ $fn failed${RESET}"
    else
      warn "Function $fn not defined; skipping."
    fi
  done

}

# starting welcome
WELCOME() {
  echo "====================================="
  echo "🚀 Starting Void Linux setup..."
  echo "====================================="
}

# reslov.conf (dns)
DNS() {
  local src="$HOME/dotfiles/my-config/myroot/etc/resolv.conf"
  if [[ -f "$src" ]]; then
    sudo chattr -i /etc/resolv.conf
    sudo cp -a "$src" /etc/resolv.conf
    success "/etc/resolv.conf updated"
  else
    error "reslov.conf clone failed"
    warn "resolv.conf source not found: $src"
  fi
  sudo chattr +i /etc/resolv.conf
}

# localtime
LOCALTIME() {
  sudo ln -sf /usr/share/zoneinfo/Africa/Cairo /etc/localtime || error "failed to link localtime"
  if command -v chronyc >/dev/null 2>&1; then
    sudo chronyc makestep || error "chronyc makestep failed"
  fi
}

# update time
TIME() {
  if command -v chronyc >/dev/null 2>&1; then
    sudo chronyc makestep || true
  fi
  if command -v hwclock >/dev/null 2>&1; then
    sudo hwclock --systohc || true
  fi
  success "Time updated"
}

# update system & xbps
UPDATE_SYSTEM() {
  info "🔄 Updating system..."
  sudo xbps-install -Syu
  sudo xbps-install -u xbps || true
  sudo xbps-install -Syu
}

# fzf
FZF_ENSURE() {
  if ! command -v fzf >/dev/null 2>&1; then
    info "Installing fzf..."
    sudo xbps-install -Suy fzf || error "failed to install fzf"
  fi
}

# fzf / package selection ---------------------------------------------------
SELECT_PACKAGES_FZF() {
  REQUIRE_CMD fzf

  local groups=(
    base
    system_performance
    intel_drivers
    gui_base
    dwm
    network_services
    sound_pulseaudio
    sound_pipewire
    bluetooth
    privacy
    lightdm
    base_apps
    desktop_gui_i3
    fonts_themes
    xorg_drivers
    boot_grub
    xmonad_requirements
    docker
  )

  local selected
  mapfile -t selected < <(
    printf "%s\n" "${groups[@]}" |
      fzf --multi \
        --reverse \
        --prompt="Select package groups > " \
        --header="TAB = select | ENTER = confirm"
  )

  [[ ${#selected[@]} -eq 0 ]] && {
    warn "Nothing selected."
    return 1
  }

  local selected_pkgs=()

  for group in "${selected[@]}"; do
    if declare -p "$group" &>/dev/null; then
      declare -n ref="$group"
      selected_pkgs+=("${ref[@]}")
    else
      warn "Package group not defined: $group"
    fi
  done

  if [[ ${#selected_pkgs[@]} -eq 0 ]]; then
    error "No packages resolved from selected groups."
  fi

  echo
  info "Packages to be installed:"
  printf "• %s\n" "${selected_pkgs[@]}"

  echo
  read -rp "Confirm installation? (y/N): " confirm
  [[ $confirm =~ ^[Yy]$ ]] || {
    warn "Canceled."
    return 0
  }

  sudo xbps-install -Suy "${selected_pkgs[@]}"
}

# Move home contents to backup ------------------------------------------------
MV_HOME() {
  mkdir -p "$HOME/bak"
  find "$HOME" -mindepth 1 -maxdepth 1 ! -name "dotfiles" ! -name "bak" -exec mv {} "$HOME/bak/" \; || true
}

# install using pipx
PIPX_APP() {
  if command -v pipx >/dev/null 2>&1; then
    pipx install pywal16 || error "pipx: failed to install pywal16"
  else
    error "pipx not present; skipping pywal16 install"
  fi
}


# user directories
MK_USER_DIRS() {
  home_dirs=(
    "$HOME/Desktop"
    "$HOME/Downloads"
    "$HOME/Pictures/screenshots"
    "$HOME/.config/tmux/plugins"
    "$HOME/Music/playlists/"
    "$HOME/Music/songs/"
    "$HOME/.config/tmux/templates/ "
    "$HOME/.ssh"
  )

  for d in "${home_dirs[@]}"; do
    mkdir -p "$d"
    success "Created (user) $d"
  done
}

# root directories
MK_ROOT_DIRS() {
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
    success "Created (root) $d"
  done
}

# stow
STOW() {
  if command -v stow >/dev/null 2>&1; then
    (cd "$DOTFILES" && stow .) || error "stow failed"
    success "stow completed"
  else
    error "stow not installed"
  fi
}

# copy configuration files safely
RSYNC() {
  local base="$HOME/dotfiles/my-config/myroot"
  declare -A pairs=(
    ["$base/etc/modprobe.d/blacklist.conf"]="/etc/modprobe.d/"
    ["$base/etc/X11/xorg.conf.d/"]="/etc/X11/xorg.conf.d/"
    ["$base/etc/xdg/autostart/nm-applet.desktop"]="/etc/xdg/autostart/"
    ["$base/etc/polkit-1/rules.d/my-safe.rules"]="/etc/polkit-1/rules.d/"
    ["$base/etc/lightdm/lightdm.conf"]="/etc/lightdm/"
    ["$base/etc/lightdm/lightdm-gtk-greeter.conf"]="/etc/lightdm/"
    ["$base/usr/share/fonts/"]="/usr/share/fonts/"
    ["$HOME/dotfiles/my-config/myroot/myhome/.config/tmux/tmux.conf"]="$HOME/.config/tmux/"
    ["$HOME/dotfiles/my-config/myroot/myhome/.config/tmux/tmux.conf.pack2"]="$HOME/.config/tmux/"
    ["$HOME/dotfiles/my-config/myroot/myhome/.config/tmux/templates/"]="$HOME/.config/tmux/templates/"
    ["$HOME/dotfiles/.config/fish/"]="/root/.config/"
    ["$HOME/dotfiles/fcrontab/"]="/var/spool/fcron/"
    ["$base/usr/share/themes/"]="/usr/share/themes/"
    ["$base/etc/default/grub"]="/etc/default/grub"
    ["$base/boot/grub/themes/"]="/boot/grub/themes/"
    ["$HOME/dotfiles/my-config/docker-compose.yml"]="/mnt/srv/docker/comp/docker-compose.yml"
    ["$base/etc/hosts"]="/etc/hosts"
    ["$base/etc/hostname"]="/etc/hostname"
    ["$base/usr/share/plymouth/themes/"]="/usr/share/plymouth/themes/"
    ["$base/usr/share/xsessions/"]="/usr/share/xsessions/"
    ["$base/myhome/.ssh/agent/"]="$HOME/.ssh/agent/"
    ["$base/myhome/.ssh/config"]="$HOME/.ssh/config"
    ["$base/myhome/.ssh/known_hosts"]="$HOME/.ssh/known_hosts"
  )

  for src in "${!pairs[@]}"; do
    dest=${pairs[$src]}
    if [[ -e "$src" ]]; then
      sudo rsync -aAXv "$src" "$dest"
      success "rsynced $src -> $dest"
    else
      warn "Source not found: $src. Skipping."
    fi
  done
}

# user touch
MK_FILES() {
  touch_files=(
    "$HOME/mpd/mpd.db"
    "$HOME/mpd/mpd.pid"
    "$HOME/mpd/mpdstate"
    "$HOME/mpd/mpd.log"
  )

  for d in "${touch_files[@]}"; do
    touch "$d"
    success "Created file $d"
  done
}

# privileges / ownership ----------------------------------------------------
PRIVILEGES() {
  sudo chown -R "$USER:$USER" "$HOME" || error "chown user home failed"
  if [[ -e /var/run/docker.sock ]]; then
    sudo chown -R "$USER:$USER" /var/run/docker.sock || true
  fi

  sudo chmod 755 "$HOME" || true

  # apply suid only if the target exists
  SAFE_CHMOD_SUID "/usr/bin/poweroff"
  SAFE_CHMOD_SUID "/usr/sbin/poweroff"

  SAFE_CHMOD_SUID "/usr/bin/reboot"
  SAFE_CHMOD_SUID "/usr/sbin/reboot"

  SAFE_CHMOD_SUID "/usr/bin/sleep"
  SAFE_CHMOD_SUID "/usr/sbin/sleep"

  SAFE_CHMOD_SUID "/usr/bin/zzz" || true
  SAFE_CHMOD_SUID "/usr/sbin/zzz" || true

  SAFE_CHMOD_SUID "/usr/sbin/hostname"
  SAFE_CHMOD_SUID "/usr/bin/hostname"

  # avoid recursively chowning all logs blindly, only chown common folders if they exist
  if [[ -d /var/log ]]; then
    sudo chown -R "$USER:$USER" /var/log || error "chown /var/log may have failed"
  fi
}

# dwm & dwmblocks
DWM() {
  local dwmdir="$HOME/dotfiles/.config/dwm/dwm"
  if [[ -d "$dwmdir" ]]; then
    cd "$dwmdir"
    if sudo make clean install; then
      success "dwm installed"
    else
      error "dwm build/install failed"
    fi
  else
    error "dwm directory not found: $dwmdir"
  fi

  local blocksdir="$HOME/dotfiles/.config/dwm/dwmblocks"
  if [[ -d "$blocksdir" ]]; then
    cd "$blocksdir"
    if sudo make clean install; then
      success "dwmblocks installed"
    else
      error "dwmblocks build/install failed"
    fi
  fi

  cd "$DOTFILES" || true
}

# change shell to fish (user + root)
SHELL() {
  if command -v fish >/dev/null 2>&1; then
    chsh -s /usr/bin/fish || error "chsh user failed"
    #    sudo chsh -s /usr/bin/fish root || error "chsh root failed"
  else
    warn "fish not found; skipping chsh"
  fi
}

# services
SERVICES() {
  services=(
    NetworkManager
    agetty-tty1
    agetty-tty2
    dbus
    dhcpcd
    earlyoom
    chronyd
    fake-hwclock
    lightdm
    preload
    zramen
    udevd
    elogind
    fcron
    ufw
    rsyslogd
  )
  for svc in "${services[@]}"; do
    if [ -d "/etc/sv/$svc" ]; then
      sudo ln -sf "/etc/sv/$svc" /var/service/
      success "Enabled (or fixed) $svc"
    else
      info "Service $svc not found in /etc/sv"
    fi
  done

  #For current in /var/service/*; do
  # svc_name=$(basename "$current")
  #if [[ ! " ${services[*]} " =~ " ${svc_name} " ]]; then
  # sudo rm -rf "/var/service/$svc_name"
  #echo "🗑️ Removed service: $svc_name"
  # else
  #  info "Kept service: $svc_name"
  #fi
  # done
}

# install Tpm for tmux and install plugins
TMUX() {
  local tpm_dir="$HOME/.config/tmux/plugins/tpm"
  if [[ ! -d "$tpm_dir" ]]; then
    git clone https://github.com/tmux-plugins/tpm "$tpm_dir" || error "TPM clone failed"
  else
    info "Reinstall TPM "
    sudo rm -r $tpm_dir || error "Failed remove TPM"
    git clone https://github.com/tmux-plugins/tpm "$tpm_dir" || error "TPM clone failed"
  fi

  mkdir -p "$HOME/.config/tmux/templates"

  if [[ -x "$tpm_dir/bin/install_plugins" ]]; then
    "$tpm_dir/bin/install_plugins" || error "TPM install plugins failed"
  else
    warn "TPM install script not executable or not found"
  fi
}

# install script for mpv
MPV() {
  local mpv_repo="$HOME/.config/mpv"
  if [[ ! -d "$mpv_repo" ]]; then
    git clone --depth 1 --filter=blob:none --sparse https://github.com/mz2012007/mpv.git "$mpv_repo" || {
      error "MPV clone failed"
      return 1
    }
    (cd "$mpv_repo" && git sparse-checkout set scripts) || error "sparse-checkout set failed"
  else
    info "mpv config already exists"
  fi
  cd $DOTFILES
}
# my custom xbps packages
MY_PKGS() {
  local pkgdir="$HOME/dotfiles/pkg-xbps"
  if [[ -d "$pkgdir" ]]; then
    cd "$pkgdir"
    sudo xbps-rindex -a ./*.xbps || warn "xbps-rindex failed"
    sudo xbps-install -y --repository="$PWD" ccze || warn "xbps-install custom pkgs may have failed"
    cd "$DOTFILES" || true
  else
    warn "pkg-xbps directory not found: $pkgdir"
  fi
}

# fonts
FONTS() {
  if command -v fc-cache >/dev/null 2>&1; then
    fc-cache -fv || warn "fc-cache may have failed"
    success "Fonts updated"
  fi
}

# groups
GROUPS() {
  local groups=(
    adm dialout lightdm plugdev storage wheel audio _pipewire disk lp polkitd sys xbuilder bin dnsmasq mail
    pulse tape _dhcpcd bluetooth fcron mpd pulse-access tty _uuidd cdrom floppy root usbmon chrony input network
    rtkit users daemon kmem nogroup scanner utmp dbus kvm optical sgx video
  )

  for svc in "${groups[@]}"; do
    sudo usermod -aG "$svc" "$USER" || warn "usermod failed for group $svc"
    success "Added to group $svc"
  done
}

# cashe
CACHE() {
  sudo tee /etc/sysctl.conf >/dev/null <<'EOF'
vm.swappiness = 60
vm.vfs_cache_pressure = 50
vm.dirty_ratio = 10
vm.dirty_background_ratio = 5
vm.min_free_kbytes = 65536
vm.dirty_writeback_centisecs = 1500
vm.dirty_expire_centisecs = 3000
vm.page-cluster = 0
EOF

  sudo sysctl --system || warn "sysctl --system may have warnings"
}

# ufw
PRIVACY() {
  sudo ufw default deny incoming
  sudo ufw default allow outgoing
  #sudo ufw allow 22/tcp
  sudo ufw enable || warn "ufw enable may have failed"
}

# Script to configure Plymouth + dracut + GRUB
PLYMOUTH () {
  echo "2️⃣ Setting default Plymouth theme..."
  if ! command -v plymouth-set-default-theme >/dev/null 2>&1; then
    error "plymouth not installed; skipping plymouth/grub steps"
    return
  fi

  echo
  echo "Listing available Plymouth themes..."
  mapfile -t options < <(plymouth-set-default-theme -l 2>/dev/null || true)
  if [[ ${#options[@]} -eq 0 ]]; then
    warn "No plymouth themes found."
    return
  fi

  REQUIRE_CMD fzf
  THEME=$(printf "%s\n" "${options[@]}" | fzf --prompt="Choose the plymouth theme > ") || true
  if [[ -z "${THEME:-}" ]]; then
    warn "No theme selected, skipping."
    return
  fi

  sudo plymouth-set-default-theme "$THEME"
  sudo plymouth-set-default-theme -R "$THEME" || error "plymouth theme rebuild may have failed"
}

GRUB() {
  if command -v grub-mkconfig >/dev/null 2>&1; then
    sudo grub-mkconfig -o /boot/grub/grub.cfg || error "grub-mkconfig may have failed"
  fi

  success "Plymouth and GRUB steps done (if applicable)"
}

# finish
FINISH() {
  echo "====================================="
  echo "🎉 System setup complete!"
  echo "📂 Logs saved to $LOGFILE"
  echo "🔄 Reboot to apply configs"
  echo "====================================="

  read -rp "Reboot now? [y/N]: " answer
  [[ $answer == [Yy]* ]] && sudo reboot
}

# trap to cleanup sudo refresh process
trap 'CLEANUP' EXIT

# main ----------------------------------------------------------------------
main() {
  SUDO_PRIV
  FZF_ENSURE
  LOGS
  RUN_SETUP
}

main "$@"
