######################################################################
#                        Package Management                           #
######################################################################
function pkg
    if test (count $argv) -eq 0
        echo "Usage:"
        echo "  pypkg <pkg>      → Basic info"
        echo "  pypkg -f <pkg>   → Full info"
        return
    end

    set full 0
    if test "$argv[1]" = -f
        set full 1
        set pkg $argv[2]
    else
        set pkg $argv[1]
    end

    if test -z "$pkg"
        echo "No package name"
        return
    end

    # check repo / installed
    xbps-query -R $pkg >/dev/null 2>&1
    set in_repo $status

    xbps-query $pkg >/dev/null 2>&1
    set installed $status

    if test $in_repo -ne 0 -a $installed -ne 0
        echo "Package not found"
        return
    end

    # choose source
    if test $installed -eq 0
        set info (xbps-query -S $pkg)
        set state "☑️"
        set install_date (string match -r 'install-date.*' $info | string split ': ' | tail -n1)
    else
        set info (xbps-query -R $pkg)
        set state "❎"
        set install_date -
    end

    function _field --argument name
        string match -r "^$name.*" $info | string split ': ' | tail -n1
    end

    clear
    echo "📦 Package : $pkg"
    echo

    echo " 🌐 Homepage   : " (string replace -r '^homepage:\s*' '' (string match -r '^homepage:.*' $info))
    echo " 📑 Desc       : " (string replace -r '^short_desc:\s*' '' (string match -r '^short_desc:.*' $info))
    echo " 📦 Size       : " (string replace -r '^filename-size:\s*' '' (string match -r '^filename-size:.*' $info))
    echo " 🔖 Version    : " (string replace -r '^pkgver:\s*' '' (string match -r '^pkgver:.*' $info))
    echo " 🏷️ License    : " (string replace -r '^license:\s*' '' (string match -r '^license:.*' $info))
    echo " ⚙️ Maintainer : " (string replace -r '^maintainer:\s*' '' (string match -r '^maintainer:.*' $info))

    if test "$install_date" = -
        echo " 📥 State      : $state"
    else
        echo " 📥 State      : $state / $install_date"
    end

    test $full -eq 0; and return

    echo
    echo "===================="
    echo " ❄️ Dependencies"
    echo "===================="

    set run_dep (string match -r 'run_depends' $info)
    if test -z "$run_dep"
        echo "No dependencies"
    else
        set start (contains -i $run_dep $info)
        for i in (seq (math $start + 1) (count $info))
            string match -r 'shlib-|short_desc' $info[$i]; and break
            echo " 📦 " (string trim $info[$i])
        end
    end

    echo
    echo "=============================="
    echo " ❄️ Shared Library Requires"
    echo "=============================="

    set shreq (string match -r 'shlib-requires' $info)
    if test -z "$shreq"
        echo "No shared libraries required"
    else
        set start (contains -i $shreq $info)
        for i in (seq (math $start + 1) (count $info))
            string match -r short_desc $info[$i]; and break
            echo " 🔗 " (string trim $info[$i])
        end
    end

    echo
    echo "=============================="
    echo " ❄️ Shared Library Provides"
    echo "=============================="

    set shprov (string match -r 'shlib-provides' $info)
    if test -z "$shprov"
        echo "No shared libraries provided"
    else
        set start (contains -i $shprov $info)
        for i in (seq (math $start + 1) (count $info))
            string match -r 'shlib-requires|short_desc' $info[$i]; and break
            echo " 🔗 " (string trim $info[$i])
        end
    end
end

function i1
    set sel (xbps-query -Rs '' | awk '{print $2}' | fzf \
        --prompt='xbps> ' \
        --layout=reverse \
        --preview-window=right:65%:wrap \
        -m \
        --bind 'ctrl-d:preview-half-page-down,ctrl-u:preview-half-page-up' \
        --preview '
            set pkg $(echo {} | sed "s/-[0-9].*//")

            echo "### STATUS ###"
            if xbps-query "$pkg" >/dev/null 2>&1
                echo "INSTALLED"
            else
                echo "NOT INSTALLED"
              end

            if xbps-query -H 2>/dev/null | grep -q "$pkg"
                echo "HOLD: YES"
            else
                echo "HOLD: NO"
              end

            echo
            echo "### INFO ###"
            xbps-query -R "$pkg" 2>/dev/null

            if xbps-query "$pkg" >/dev/null 2>&1
            else
              echo
              echo "### INSTALL SIMULATION ###"
              xbps-install -Svn "$pkg" 2>/dev/null
          end
        ')

    test -z "$sel"; and return

    set pkg $sel

    xbps-query $pkg >/dev/null 2>&1
    set installed $status

    xbps-query -H 2>/dev/null | grep -q "$pkg"
    set hold_status $status

    clear
    echo "Package : $pkg"
    if test $installed -eq 0
        echo "Status  : INSTALLED"
    else
        echo "Status  : NOT INSTALLED"
    end
    test $hold_status -eq 0; and echo "Hold    : YES"; or echo "Hold    : NO"
    echo

    set i 1
    if test $installed -eq 0
        echo "$i) Remove"
        set remove_opt $i
        set i (math $i + 1)
    else
        echo "$i) Install"
        set install_opt $i
        set i (math $i + 1)
    end

    if test $hold_status -eq 0
        echo "$i) Unhold"
        set unhold_opt $i
        set i (math $i + 1)
    else
        echo "$i) Hold"
        set hold_opt $i
        set i (math $i + 1)
    end

    echo "$i) Cancel"
    set cancel_opt $i

    read -P "> " choice

    switch $choice
        case $remove_opt
            sudo xbps-remove $pkg
        case $install_opt
            sudo xbps-install $pkg
        case $hold_opt
            sudo xbps-pkgdb -m hold $pkg
        case $unhold_opt
            sudo xbps-pkgdb -m unhold $pkg
        case $cancel_opt
            return
    end
end

function u
    sudo xbps-install -Su
end
######################################################################
#                              End Scripts                              #
######################################################################
