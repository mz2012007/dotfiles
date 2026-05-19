######################################################################
#                            countfiles                               #
######################################################################
function countfiles
    if test (count $argv) -gt 0
        set dir $argv[1]
    else
        set dir ~
    end

    for t in files links directories
        switch $t
            case files
                set type f
            case links
                set type l
            case directories
                set type d
        end
        find $dir -type $type | wc -l | tr -d '\n'
        echo " $t"
    end 2>/dev/null
end

######################################################################
#                              End Scripts                              #
######################################################################
