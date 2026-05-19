######################################################################
#
######################################################################
function extract
    if test (count $argv) -eq 0
        echo "Usage: extract <archive> ..."
        return
    end

    for archive in $argv
        if test -f $archive
            switch $archive
                case '*.tar.bz2' '*.tbz2'
                    tar xvjf $archive
                case '*.tar.gz' '*.tgz'
                    tar xvzf $archive
                case '*.bz2'
                    bunzip2 $archive
                case '*.rar'
                    rar x $archive
                case '*.gz'
                    gunzip $archive
                case '*.tar'
                    tar xvf $archive
                case '*.zip'
                    set folder (string replace -r '\.zip$' '' $archive)
                    unzip $archive -d $folder
                case '*.Z'
                    uncompress $archive
                case '*.7z'
                    7z x $archive
                case '*'
                    echo "don't know how to extract '$archive'..."
            end
        else
            echo "'$archive' is not a valid file!"
        end
    end
end

######################################################################
#                              End Scripts                            #
######################################################################
