######################################################################
#                     Editor & File Utilities                         #
######################################################################
function n
    nvim $argv
end
complete -c n -w nvim

######################################################################
function nv
    nvim-qt $argv
end
complete -c n -w nvim-qt

######################################################################
function cat
    bat --paging=never $argv
end
complete -c cat -w bat

######################################################################
function af
    # Set function directory
    set -l func_dir $HOME/.config/fish/myfunc
    mkdir -p $func_dir # ensure directory exists

    # Check if filename argument is provided
    if test (count $argv) -eq 0
        echo "Usage: af <filename>"
        return 1
    end

    # Set full file path
    set -l file $func_dir/$argv[1]

    # Check if file exists
    if test -f $file
        # open existing file in nvim
        nvim $file
    else
        # create new file with shebang
        echo "#!/usr/bin/env bash" >$file
        chmod +x $file # make executable
        nvim $file
    end
end
complete -c af -f -a "(ls $HOME/.config/fish/myfunc 2>/dev/null)" -n true

######################################################################
#                              End Scripts                              #
######################################################################
