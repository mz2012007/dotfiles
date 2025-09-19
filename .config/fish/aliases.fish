function history
    nvim ~/.local/share/fish/fish_history
end
######################################
function edit
    nvim ~/.config/fish/aliases.fish
end
######################################
function search
    sudo xbps-query -Rs $argv
end
######################################
function u
    sudo xbps-install -Su
end
######################################
function i
    sudo xbps-install -S $argv
end
######################################
function r
    sudo xbps-remove $argv
end
######################################
function q
    sudo xbps-query -Rs $argv
end
######################################
function up
    sudo sv up $argv
end
######################################
function down
    sudo sv down $argv
end
######################################
function stop
    sudo sv stop $argv
end
######################################
function start
    sudo sv start $argv
end
######################################
function restart
    sudo sv restart $argv
end
######################################
function hipernate
    ~/.config/scripts/zzz
end
######################################
function 1
    fastfetch
end
######################################
function 2
    tmux
end
######################################
function 3
    tmux attach
end
######################################
function n
    nvim $argv
end
######################################
function cat
    bat $argv
end
######################################
function 4
    $HOME/.config/polybar/scripts/wallz.py
end
######################################
function +x
    sudo chmod +x $argv
end
######################################
function h
    history
end
######################################
function logs
    sudo tail -f /var/log/messages | ccze -A | awk '{ $1=strftime("%b %d %H:%M:%S"); print }' $argv
end
######################################
function l
    eza --color-scale-mode=gradient --icons --hyperlink -AlMHlioF --total-size --show-symlinks $argv
end
######################################
function ch
    sudo ~/scripts/chroot.sh $argv
end
######################################
function s
    ~/scripts/services.sh
end
