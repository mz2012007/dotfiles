if status is-interactive
    # Commands to run in interactive sessions can go here
end
source ~/.config/fish/aliases.fish
set -g fish_greeting
set -g EDITOR neovim
set -g PATH $HOME/.config/tmux/templets/bin:$PATH


if not set -q TMUX
    tmux attach -t main || tmux new -s main
end



#set -gx PATH "~/.config/tmux/templets/bin" $PATH
#set -gx PATH "$HOME/.nix-profile/bin:$PATH"
#fastfetch
#if test -e /home/(whoami)/.nix-profile/etc/profile.d/nix.sh
#    source /home/(whoami)/.nix-profile/etc/profile.d/nix.sh
#end 


