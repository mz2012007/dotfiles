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
