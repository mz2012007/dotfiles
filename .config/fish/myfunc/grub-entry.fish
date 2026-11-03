if status is-interactive
    set -l script_name (string match -r '(^| )run_script=[^ ]+' </proc/cmdline | string replace 'run_script=' '')

    if test -n "$script_name"; and string match -rq '^[a-zA-Z0-9_-]+$' -- "$script_name"
        set -l script_path "$HOME/scripts/grub/$script_name.fish"

        if test -x "$script_path"
            "$script_path"
        end
    end
end
