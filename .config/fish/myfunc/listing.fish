######################################################################
#                     Listing Utilities                               #
######################################################################
function l
    set opts
    set valid_paths
    set invalid_paths

    for arg in $argv
        # options
        if string match -qr '^-' -- $arg
            set opts $opts $arg
            continue
        end

        # try glob expansion manually
        set matches (ls -d -- $arg 2>/dev/null)

        if test (count $matches) -gt 0
            set valid_paths $valid_paths $matches
        else if test -e $arg
            set valid_paths $valid_paths $arg
        else
            set invalid_paths $invalid_paths $arg
        end
    end

    # default to current dir if nothing valid
    if test (count $valid_paths) -eq 0
        set valid_paths .
    end

    # show valid
    eza -AlMioF --color=always --icons --show-symlinks $opts $valid_paths

    # show invalid paths
    if test (count $invalid_paths) -ne 0
        set_color red
        echo "Not found:"
        set_color normal

        for i in $invalid_paths
            set_color yellow
            echo "  $i"
        end
        set_color normal
    end
end

complete -c l -w eza

######################################################################
function sz
    du --summarize -h $argv
end
complete -c sz -w ls -A

######################################################################
function lsize
    eza -AlioF --color=always --icons --show-symlinks $argv
end
complete -c l -w ls -A

######################################################################
function la
    command ls -Alh $argv
end # show hidden files

######################################################################
function lsl
    command ls -aFh --color=always $argv
end # add colors and file type extensions

######################################################################
function lx
    command ls -lXBh $argv
end # sort by extension

######################################################################
function lk
    command ls -lSrh $argv
end # sort by size

######################################################################
function lc
    command ls -ltcrh $argv
end # sort by change time

######################################################################
function lu
    command ls -lturh $argv
end # sort by access time

######################################################################
function lr
    command ls -lRh $argv
end # recursive ls

######################################################################
function lt
    command ls -ltrh $argv
end # sort by date

######################################################################
function lm
    command ls -alh | more $argv
end # pipe through 'more'

######################################################################
function lw
    command ls -xAh $argv
end # wide listing format

######################################################################
function ll
    command ls -Fls $argv
end # long listing format

######################################################################
function labc
    command ls -lap $argv
end # alphabetical sort

######################################################################
function lf
    eza -lf --color=always --icons --show-symlinks $argv
end # files only

######################################################################
function ld
    eza -lDF --color=always --icons --show-symlinks $argv
end # directories only

######################################################################
function lla
    command ls -Al $argv
end # List and Hidden Files

######################################################################
function las
    command ls -A $argv
end # Hidden Files

######################################################################
function lls
    command ls -l $argv
end # List

######################################################################
function lg
    clear
    if test (count $argv) -gt 3 || test (count $argv) -eq 0
        echo "Usage: lg <path> <pattern>"
        return
    end

    if test (count $argv) -eq 1
        set path $pwd
        set pattern $argv[1]
    else
        set path $argv[1]
        set pattern $argv[2]
    end

    set col9_colored ""

    set pattern_list ""
    for f in (ls -1A $path)
        string match -iq "*$pattern*" -- $f; or continue

        for t in $f
            set pattern_list (echo $t | awk '{print $1}')
        end

        eza -AlMioF --color=always --total-size --show-symlinks $path \
            | awk -v pat="$pattern_list" '$9 ~ pat' \
            | while read -l line
            set cols (string split --no-empty ' ' -- $line)

            set col9 $cols[9]

            set clean (string replace -ra '\x1b\[[0-9;]*m' '' -- $col9)

            set col9_colored ""

            for c in (string split "" -- $clean)
                if string match -iq "$pattern" $c
                    set col9_colored "$col9_colored"(printf "\e[31m%s\e[0m" $c)
                else
                    set col9_colored "$col9_colored"(printf "\e[34m%s\e[0m" $c)
                end
            end

            printf "%s " $cols[1..8]
            printf "%s " $col9_colored
            printf "%s " $cols[10..-1]
            printf "%s\n" ""
        end
    end | bat
end

function toggle_case
    set input $argv[1]
    set output ""
    for c in (string split "" $input)
        if string match -qr "[a-z]" $c
            set output "$output"(string upper $c)
        else if string match -qr "[A-Z]" $c
            set output "$output"(string lower $c)
        else
            set output "$output"$c
        end
    end
    echo $output
end

function color

    if test (count $argv) -ge 3 || test (count $argv) -le 1
        echo "Usage: lg <words> <pattern>"
        return
    end

    set pattern $argv[2]

    set clean (string replace -ra '\x1b\[[0-9;]*m' '' -- $argv[1])

    set colored ""

    for c in (string split "" -- $clean)
        if string match -iq "$pattern" $c
            set colored "$colored"(printf "\e[31m%s\e[0m" $c)
        else
            set colored "$colored"(printf "\e[34m%s\e[0m" $c)
        end
    end
    printf "%s " $colored
end

######################################################################

######################################################################
#                              End Scripts                              #
######################################################################
