if status is-interactive
    # Commands to run in interactive sessions can go here
end

source ~/.config/fish/aliases.fish

set -g fish_greeting
set -g EDITOR nvim

if not contains $HOME/.local/bin $fish_user_paths
    set -U fish_user_paths $HOME/.config/tmux/templets/bin:$PATH
    set -U fish_user_paths $HOME/.local/bin $fish_user_paths

end

if not set -q TMUX
    tmux attach -t main || tmux new -s main
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
bind \ca beginning-of-line

bind \ce end-of-line

bind \cb backward-word

bind \cw forward-word

bind \cd backward-kill-word

bind \ch fzf-tmux
#____________________________________________________________________________#

#set -gx PATH "~/.config/tmux/templets/bin" $PATH
#set -gx PATH "$HOME/.nix-profile/bin:$PATH"
#fastfetch
#if test -e /home/(whoami)/.nix-profile/etc/profile.d/nix.sh
#    source /home/(whoami)/.nix-profile/etc/profile.d/nix.sh
#end 
