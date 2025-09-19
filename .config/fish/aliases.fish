function history
    nvim ~/.local/share/fish/fish_history
end
######################################################################
function edit
    nvim ~/.config/fish/aliases.fish
end
######################################################################
function search
    sudo xbps-query -Rs $argv
end
complete -c search -w xbps-query
######################################################################
function u
    sudo xbps-install -Su
end
######################################################################
function i
    sudo xbps-install -S $argv
end
complete -c i -w xbps-install
######################################################################
function r
    sudo xbps-remove $argv
end
complete -c r -w xbps-remove
######################################################################
function q
    sudo xbps-query -Rs $argv
end
complete -c q -w xbps-query
######################################################################
abbr -a restart 'sudo sv restart'
abbr -a up 'sudo sv up'
abbr -a down 'sudo sv down'
abbr -a stop 'sudo sv stop'
abbr -a start 'sudo sv start'
######################################################################
function hipernate
    ~/.config/scripts/zzz
end
######################################################################
function 1
    fastfetch
end
######################################################################
function 2
    tmux
end
######################################################################
function 3
    tmux attach
end
######################################################################
function n
    nvim $argv
end
complete -c n -w nvim
######################################################################
function cat
    bat $argv
end
complete -c cat -w bat
######################################################################
function 4
    $HOME/.config/polybar/scripts/wallz.py
end
######################################################################
function +x
    sudo chmod +x $argv
end
complete -c +x -w chmod
######################################################################
function h
    history
end
######################################################################
function logs
    sudo tail -f /var/log/messages | ccze -A | awk '{ $1=strftime("%b %d %H:%M:%S"); print }' $argv
end
######################################################################
function l
    eza --color-scale-mode=gradient --icons --hyperlink -AlMHlioF --total-size --show-symlinks $argv
end
complete -c l -w eza
######################################################################
function ch
    sudo ~/scripts/chroot.sh $argv
end
######################################################################
function s
    ~/scripts/services.sh
end
######################################################################
