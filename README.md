## My Void Linux Bootstrap System Configuration

# Disclaimer
This repository is a hobby project for Void Linux bootstrap system configuration.

⚠️ Use at your own risk. I provide no guarantees and take no responsibility for any damage or data loss.

# It’s strongly advised to run this script in a virtual machine first. This way, you can test all changes safely without risking your main system.

# What it gives you

runit (init system)

i3 (window manager)

polybar

conky

picom

lightdm

grub

lazy.nvim

tmux

etc .....



# Installation

After a fresh install of Void Linux base (glibc):

This is the distribution link https://voidlinux.org/

 update repository
<pre>sudo xbps-install -S</pre>

 update xbps package manager
<pre>sudo xbps-install xbps</pre>

 update system
<pre>sudo xbps-install -Syu</pre>

 insatll git 
<pre>sudo xbps-install -S git</pre>

git clone repository in home 
<pre>cd ~
git clone https://github.com/mz2012007/dotfiles</pre>

insatll the Configuration
<pre>cd ~/dotfiles
sudo ./install.sh</pre> 



#  To edit keybind 

<pre>nano ~/.config/i3/config</pre>

# Keybinds

$mod = Mod4 (Super key)

Mod1 = Alt

# Apps

$mod+a → alacritty

$mod+p → thunar

$mod+c → chromium (with nice/ionice)

$mod+x → memreduct.sh (custom script)

$mod+l → sudo lightdm-gtk-greeter-settings

$mod+d → rofi -show drun -show-icons

$mod+m → parole

Print → flameshot gui

Mod1+Tab → rofi -show window -show-icons

$mod+Return → pkill polybar

$mod+Shift+t → lxappearance

# Gaps

$mod+minus → decrease inner gap

$mod+equal → increase inner gap

# Window focus

$mod+ArrowKeys → move focus

# Move windows

$mod+Shift+ArrowKeys → move window

# Splits

$mod+h → horizontal split

$mod+v → vertical split

# Layouts

F11 → fullscreen

$mod+s → stacking layout

$mod+t → tabbed layout

$mod+e → toggle split

# Floating / tiling

$mod+Shift+space → toggle floating

$mod+z → toggle focus between floating/tiling

# Workspaces

$mod+1..0 → switch workspace

$mod+Shift+1..0 → move container to workspace

# i3 controls

$mod+Shift+c → reload config

$mod+Shift+r → restart i3

$mod+Shift+e → exit i3 (with confirmation dialog)

$mod+r → resize mode












