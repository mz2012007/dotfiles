######################################################################
#                        IP address lookup                            #
######################################################################
function myip
    # Internal IP Lookup.
    if command -v ip &>/dev/null
        echo -n "Internal IP: "
        ip addr show wlan0 | grep "inet " | awk '{print $2}' | cut -d/ -f1
    else
        echo -n "Internal IP: "
        ifconfig wlan0 | grep "inet " | awk '{print $2}'

    end

    # External IP Lookup
    echo -n "External IP: "
    curl -4 ifconfig.me
end

######################################################################
#                              End Scripts                            #
######################################################################
