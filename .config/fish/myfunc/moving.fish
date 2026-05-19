######################################################################
#                              moving                                 #
######################################################################
# Copy and go
function cpg
    if test -d $argv[2]
        cp $argv[1] $argv[2]; and cd $argv[2]
    else
        cp $argv[1] $argv[2]
    end
end

######################################################################
# Move and go
function mvg
    if test -d $argv[2]
        mv $argv[1] $argv[2]; and cd $argv[2]
    else
        mv $argv[1] $argv[2]
    end
end

######################################################################
# up N directories
function upd
    set count $argv[1]
    set path ""
    for i in (seq $count)
        set path "../$path"
    end
    cd $path
end

######################################################################
# sustom pwd 
function pwdtail
    pwd | awk -F/ '{print $(NF-1) "/" $NF}'
end

######################################################################
#                              End Scripts                            #
######################################################################
