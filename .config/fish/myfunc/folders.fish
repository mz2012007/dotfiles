######################################################################
#                     Disk & Folder Utilities                        #
######################################################################
function folders
    du -h --max-depth=1 $argv
end

######################################################################
function folderssort
    find . -maxdepth 1 -type d -print0 | xargs -0 du -sk | sort -rn $argv
end

######################################################################
function tree
    command tree -CAhF --dirsfirst $argv
end

######################################################################
function treed
    command tree -CAFd $argv
end

######################################################################
function rmd
    /bin/rm --recursive --force --verbose $argv
end # recursive remove with verbose

######################################################################
function rm
    $HOME/dev/safe-rm/safe_rm $argv
end
complete -c rm -w /usr/bin/rm

######################################################################
function ftext
    grep -iIHrn --color=always $argv[2] $argv[1] | less -R
end

######################################################################
function bata
    find $argv -exec bat {} +
end
complete -c bata -w bat

######################################################################
function trash
    $HOME/scripts/trash.sh $argv
end

######################################################################
#                              End Scripts                              #
######################################################################
