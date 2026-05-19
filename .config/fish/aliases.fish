######################################################################
# Basic Safety Aliases
######################################################################
alias cp='cp -i' # interactive copy
alias mv='mv -i' # interactive move
alias ps='ps auxf' # process tree
alias bd='cd "$OLDPWD"' # back directory

alias f="sudo find / | grep "
alias rebootsafe='sudo shutdown -r now'
alias rebootforce='sudo shutdown -r -n now'

alias do='doas'

alias app='nvim $HOME/.config/i3/config'
alias i='$HOME/scripts/fuzzypkg.sh'

alias sb='sudo btop'
alias snano="sudo nano"
alias web="cd /var/www/html"

alias da='date "+%Y-%m-%d %A %I:%M:%S %p"'

alias tp='command fzf --preview "bat --color=always --style=numbers --line-range=:500 {}"'

alias h='nvim ~/.local/share/fish/fish_history' #History
alias ea='nvim ~/.config/fish/aliases.fish' #edit aliases 
alias ef='nvim ~/.config/fish/config.fish' #edit fish config 
alias hipernate='~/.config/scripts/zzz' #hipernate
alias s='~/scripts/window-script.sh ~/scripts/services/main.sh' #runit-manager
alias 1='fastfetch'
alias 2='tmux'
alias 3='tmux attach'
alias 4='$HOME/.config/polybar/scripts/wallz.py'
alias sf='clear && source $HOME/.config/fish/config.fish' #source fish
alias mountedinfo='df -hT' #mounted point
alias diskspace='du -S | sort -n -r | more' #diskspace

#######################################################
#                    custom                            #
#######################################################
# grep / ripgrep
if type -q rg
    alias grep="rg"
else
    alias grep="/usr/bin/grep --color=auto"
end

######################################################################
# Directory Abbreviations
######################################################################
abbr -a . 'cd ..'
abbr -a .. 'cd ../..'
abbr -a ... 'cd ../../..'
abbr -a .... 'cd ../../../..'
abbr -a ..... 'cd ../../../../..'
abbr -a ...... 'cd ../../../../../..'

######################################################################
# Service Shortcuts
######################################################################
abbr -a restart 'sudo sv restart'
abbr -a up 'sudo sv up'
abbr -a down 'sudo sv down'
abbr -a stop 'sudo sv stop'
abbr -a start 'sudo sv start'

######################################################################
#                             History Shortcut                        #
######################################################################
function open

    if test (count $argv) -eq 0
        set path (yazi / )
    else
        set path $argv[1]
    end

    if test -d "$path"
        cd "$path"
        echo "Changed directory to: $path"
    else if test -f "$path"
        nvim "$path"
    else
        echo "Path does not exist: $path"
    end
end

######################################################################
#                              End Scripts                            #
######################################################################
