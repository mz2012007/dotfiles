#fisher install \
#  jorgebucaran/nvm.fish \
#  PatrickF1/fzf.fish \
#  jethrokuan/z \
#  IlanCosman/tide \
#  gazorby/fish-abbreviation-tips \
#  meaningful-ooo/sponge

# fish_greeting

if status is-interactive
    # Commands to run in interactive sessions can go here
end

# colors
#set -gx LS_COLORS 'no=00:fi=00:di=00;34:ln=01;36:ex=01;32'

# source
source $HOME/.config/fish/aliases.fish
for f in $HOME/.config/fish/functions/*.fish
    source $f
end
for n in $HOME/.config/fish/myfunc/*.fish
    source $n
end

# ENV VARIABLES
set -U fish_history_max 100000
set -gx HISTSIZE 100000
set -gx HISTFILESIZE 10000
set -gx HISTTIMEFORMAT "%F %T"

set -g fish_autosuggestion_enabled 1
set -g fish_color_autosuggestion brblack

set -gx CLICOLOR 1

set fzf_history_time_format %d-%m-%y

set -U XDG_RUNTIME_DIR /run/user/$(id -u)

set -g __fish_plugins \
    jorgebucaran/fisher \
    jorgebucaran/nvm.fish \
    patrickf1/fzf.fish \
    jethrokuan/z \
    ilancosman/tide \
    gazorby/fish-abbreviation-tips \
    meaningful-ooo/sponge

# ssh
# GPG-Agent
gpgconf --launch gpg-agent
set SSH_AGENT_PID
set -x SSH_AUTH_SOCK (gpgconf --list-dirs agent-ssh-socket)
export GPG_TTY=$(tty)
set -x GPG_TTY $(tty)
gpg-connect-agent updatestartuptty /bye >/dev/null

# XDG
set -gx XDG_DATA_HOME "$HOME/.local/share"
set -gx XDG_CONFIG_HOME "$HOME/.config"
set -gx XDG_STATE_HOME "$HOME/.local/state"
set -gx XDG_CACHE_HOME "$HOME/.cache"

# variables
set -g fish_greeting
set -Ux EDITOR nvim
set -Ux VISUAL nvim
set -Ux TERMINAL alacritty

set -gx LANG en_US.utf8
set -gx LC_ALL en_US.utf8

set -Ux NVIM_APPNAME nvim
set -Ux STARSHIP_CONFIG $HOME/.config/starship/starship.toml

fzf --fish | source

# Add directories to fish_user_paths if not already present
set -l new_paths $HOME/.config/tmux/templets/bin $HOME/.local/bin $HOME/scripts $HOME/dotfiles/.config/dwm/dwmblocks/patches

for p in $new_paths
    if not contains $p $fish_user_paths
        set -Ux fish_user_paths $p $fish_user_paths
    end
end

#######################################################
#          fisher & pluginsship                        #
#######################################################
#if not functions -q fisher
#    curl -sL https://git.io/fisher | source && fisher install jorgebucaran/fisher
#end

# Check if fisher function exists, if not install it
#if not functions -q fisher
# Download fisher installer to a temp file
#    set tmp (mktemp)
# curl -sL https://git.io/fisher -o $tmp
# Source it and wait to finish
#source $tmp
#rm $tmp

# Install the main fisher manager
#fisher install jorgebucaran/fisher
#end

if status is-interactive
    # Check if fisher exists
    if type -q fisher
        for plugin in $__fish_plugins
            if not fisher list | grep -q $plugin
                fisher install $plugin
            end
        end
    end
end

#######################################################
#          zoxide + starship + tnux                    #
#######################################################

#if type -q fastfetch
#    fastfetch
#end

#if not set -q TMUX
#    tmux attach -t main || tmux new -s main
#end

#if type -q starship
#    starship init fish | source # prompt
#end

if type -q zoxide
    zoxide init fish | source # smart cd
end

# || tmux new -s main

#____________________________________________________________________________#

# Solarized Dark & Green highlight
#set -g man_blink -o red
#set -g man_bold -o green
#set -g man_standout -b black 93a1a1
#set -g man_underline -u 93a1a1

# Solarized Light & Magenta highlight
#set -g man_blink -o red
#set -g man_bold -o magenta
#set -g man_standout -b white 586e75
#set -g man_underline -u 586e75

#____________________________________________________________________________#

# ctrl-a
bind \cb backward-word

bind \cw forward-word

bind \cs sf

bind \cd backward-kill-word

#bind \cf fzf-tmux

bind \ct trash

bind \cf tp

bind \cq $HOME/.config/tmux/templates/template1

#____________________________________________________________________________#

#set -gx PATH "~/.config/tmux/templets/bin" $PATH
#set -gx PATH "$HOME/.nix-profile/bin:$PATH"
#fastfetch
#if test -e /home/(whoami)/.nix-profile/etc/profile.d/nix.sh
#    source /home/(whoami)/.nix-profile/etc/profile.d/nix.sh
#end 
