# Fish completion for Power_save.sh
#
# Install (per-user):
#   cp Power_save.sh.fish ~/.config/fish/completions/Power_save.sh.fish
#
# Install (system-wide):
#   sudo cp Power_save.sh.fish /usr/share/fish/vendor_completions.d/
#
# Then reload:  exec fish
# Or clear cache: complete -e -c Power_save.sh

# ---------------------------------------------------------------------------
# Find the config file (mirrors the script's lookup order)
# ---------------------------------------------------------------------------
function __power_save_conf
    if set -q POWER_SAVE_CONF
        echo $POWER_SAVE_CONF
        return
    end
    for f in ./power-save.conf ~/.config/power-save.conf /etc/power-save.conf
        if test -r $f
            echo $f
            return
        end
    end
end

# ---------------------------------------------------------------------------
# Extract profile names from `PROFILES=(a b c)` inside the config
# ---------------------------------------------------------------------------
function __power_save_profiles
    set -l conf (__power_save_conf)
    test -n "$conf"; or return
    set -l line (grep -m1 -E '^[[:space:]]*PROFILES=\(' $conf)
    test -n "$line"; or return
    string replace -r '^[^(]*\(' '' $line \
        | string replace -r '\).*$' '' \
        | string split -n ' '
end

# ---------------------------------------------------------------------------
# Only complete the FIRST positional argument (no subcommand yet)
# ---------------------------------------------------------------------------
function __power_save_at_first_arg
    set -l toks (commandline -opc)
    test (count $toks) -eq 1
end

# ---------------------------------------------------------------------------
# Register completions for common invocation styles
# ---------------------------------------------------------------------------
for __ps_cmd in Power_save.sh ./Power_save.sh Power_save
    # Static subcommands
    complete -c $__ps_cmd -f -n __power_save_at_first_arg \
        -a restore -d 'Restore original values + run RESTORE_CMDS'
    complete -c $__ps_cmd -f -n __power_save_at_first_arg \
        -a status -d 'Colored table: Original vs Applied vs Current + battery'
    complete -c $__ps_cmd -f -n __power_save_at_first_arg \
        -a watch -d 'Keep iGPU DPM locked to low (Ctrl+C to stop)'
    complete -c $__ps_cmd -f -n __power_save_at_first_arg \
        -a list -d 'List available profiles from config'
    complete -c $__ps_cmd -f -n __power_save_at_first_arg \
        -a help -d 'Show help'

    # Dynamic profiles
    complete -c $__ps_cmd -f -n __power_save_at_first_arg \
        -a '(__power_save_profiles)' -d 'Apply profile'

    # Options
    complete -c $__ps_cmd -f -s h -l help -d 'Show help'
end

set -e __ps_cmd
