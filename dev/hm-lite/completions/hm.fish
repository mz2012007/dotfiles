#!/usr/bin/env fish
#
# completions/hm.fish - fish completion for HM-Lite.
#
# The file is self contained. It only uses fish builtins and it never runs
# the hm executable, therefore completing a command line can never change
# the state of a project.
#
# Enable it for the current session with:
#
#   source /path/to/hm-lite/completions/hm.fish
#
# The completion never fails the shell. When the project database cannot be
# read, the dynamic suggestions are simply not offered.
#
# Requirements: fish 3.0 or newer, the sqlite3 command line tool.

# ---------------------------------------------------------------------------
# The state of the project
# ---------------------------------------------------------------------------

# __hm_runtime_dir
# Print the runtime directory of the project. The resolution matches the hm
# executable: the environment wins, the default is ~/.config/hm-lite.
function __hm_runtime_dir
    if set -q HM_DIR; and test -n "$HM_DIR"
        echo $HM_DIR
        return 0
    end

    if not set -q HOME
        return 1
    end

    echo $HOME/.config/hm-lite
end

# __hm_db_file
# Print the path of the project database.
function __hm_db_file
    if set -q HM_DB_FILE; and test -n "$HM_DB_FILE"
        echo $HM_DB_FILE
        return 0
    end

    set -l dir (__hm_runtime_dir)
    or return 1

    echo $dir/db.sqlite
end

# __hm_context_profile
# Print the profile that scopes a command: HM_PROFILE, the active profile,
# then the default profile.
function __hm_context_profile
    if set -q HM_PROFILE; and test -n "$HM_PROFILE"
        echo $HM_PROFILE
        return 0
    end

    set -l db (__hm_db_file)
    or begin
        echo default
        return 0
    end

    if test -f $db
        set -l active (sqlite3 -readonly -noheader -list $db \
            "SELECT value FROM state WHERE key = 'active_profile';" 2>/dev/null)
        if test -n "$active"
            echo $active
            return 0
        end
    end

    echo default
end

# __hm_generation_ids
# Print the local generation numbers of the effective profile, newest first.
# An explicit --profile on the command line wins. A missing or unreadable
# database is not an error, it produces no output. The database is opened
# read only, the file is never created and never modified.
function __hm_generation_ids
    set -l db (__hm_db_file)
    or return 0

    test -f $db; or return 0

    set -l profile (__hm_context_profile)
    set -l tokens (commandline -opc)
    set -l count (count $tokens)

    for index in (seq 1 $count)
        set -l token $tokens[$index]
        switch "$token"
            case --profile
                set -l next (math $index + 1)
                if test $next -le $count
                    set profile $tokens[$next]
                end
            case '--profile=*'
                set profile (string replace -- '--profile=' '' "$token")
        end
    end

    set -l rows (sqlite3 -readonly -noheader -list $db \
        'SELECT pr.name || char(9) || g.number
           FROM generations g
           JOIN profiles pr ON pr.id = g.profile_id
          ORDER BY g.created_at DESC, g.id DESC;' 2>/dev/null)

    for row in $rows
        set -l parts (string split \t -- $row)
        if test (count $parts) -ge 2; and test "$parts[1]" = "$profile"
            echo $parts[2]
        end
    end
end

# __hm_profile_names
# Print the names of the profiles, in name order. A missing or unreadable
# database is not an error, it produces no output.
function __hm_profile_names
    set -l db (__hm_db_file)
    or return 0

    test -f $db; or return 0

    sqlite3 -readonly -noheader -list $db \
        'SELECT name FROM profiles ORDER BY name;' 2>/dev/null
end

# __hm_tracked_paths
# Print the paths that the project already tracks. The database is opened
# read only, the file is never created and never modified.
function __hm_tracked_paths
    set -l db (__hm_db_file)
    or return 0

    test -f $db; or return 0

    sqlite3 -readonly -noheader -list $db \
        'SELECT path FROM paths ORDER BY path;' 2>/dev/null
end

# __hm_backup_archives
# Print the backup archives that the project owns.
function __hm_backup_archives
    set -l dir (__hm_runtime_dir)
    or return 0

    test -d $dir/backup; or return 0

    for archive in $dir/backup/hm-backup-*.tar.gz
        test -f $archive; and echo $archive
    end
end

# __hm_is_command COMMAND
# Return 0 when COMMAND is the first subcommand of hm on the current line.
# Unlike __fish_seen_subcommand_from this also checks the position, so the
# arguments of "hm profile add" do not trigger the completions of "hm add".
function __hm_is_command
    set -l tokens (commandline -opc)
    test (count $tokens) -ge 2; or return 1
    test "$tokens[1]" = hm; or return 1
    test "$tokens[2]" = "$argv[1]"
end

# __hm_profile_has_subcommand SUBCOMMAND
# Return 0 when the line is "hm profile SUBCOMMAND ...".
function __hm_profile_has_subcommand
    set -l tokens (commandline -opc)
    test (count $tokens) -ge 3; or return 1
    test "$tokens[1]" = hm; or return 1
    test "$tokens[2]" = profile; or return 1
    test "$tokens[3]" = "$argv[1]"
end

# __hm_profile_subcommand_slot
# Return 0 when the next word is the profile subcommand.
function __hm_profile_subcommand_slot
    set -l tokens (commandline -opc)
    test (count $tokens) -eq 2; or return 1
    test "$tokens[1]" = hm; or return 1
    test "$tokens[2]" = profile
end

# __hm_profile_slot SUBCOMMAND COUNT
# Return 0 when COUNT positional arguments follow the profile subcommand.
# Flags and the help option are ignored, so "profile delete --force <TAB>"
# still completes the profile name.
function __hm_profile_slot
    set -l expected $argv[1]
    set -l wanted $argv[2]
    set -l tokens (commandline -opc)

    test (count $tokens) -ge 3; or return 1
    test "$tokens[1]" = hm; or return 1
    test "$tokens[2]" = profile; or return 1
    test "$tokens[3]" = "$expected"; or return 1

    set -l count 0
    for token in $tokens[4..-1]
        switch "$token"
            case -h --help
                return 1
            case '-*'
                continue
            case '*'
                set count (math $count + 1)
        end
    end

    test $count -eq $wanted
end

# __hm_profile_path_slot
# Return 0 for a path after "hm profile add <name>".
function __hm_profile_path_slot
    set -l tokens (commandline -opc)

    test (count $tokens) -ge 4; or return 1
    test "$tokens[1]" = hm; or return 1
    test "$tokens[2]" = profile; or return 1
    test "$tokens[3]" = add; or return 1
end

# ---------------------------------------------------------------------------
# The command surface
# ---------------------------------------------------------------------------

# __hm_positional_slot SUBCOMMAND
# Return 0 when the current token is the first positional argument of the
# subcommand. Options that are already typed are ignored, so
# "hm apply --dry-run <TAB>" still offers the local generation numbers.
function __hm_positional_slot
    set -l expected $argv[1]
    set -l tokens (commandline -opc)

    test (count $tokens) -ge 2; or return 1
    test "$tokens[1]" = hm; or return 1
    test "$tokens[2]" = "$expected"; or return 1

    set -l positionals 0
    set -l skip 0

    for token in $tokens[3..-1]
        if test $skip -eq 1
            set skip 0
            continue
        end

        switch "$token"
            case -h --help
                return 1
            case --name --comment --generation --profile
                # The option consumes the next word.
                set skip 1
            case '-*'
                # An inline value or a flag, it consumes nothing else.
                continue
            case '*'
                set positionals (math $positionals + 1)
        end
    end

    test $positionals -eq 0
end

# The command itself offers no files, every subcommand decides on its own.
complete -c hm -f

complete -c hm -n '__fish_use_subcommand' -a init -d 'Initialize the HM-Lite project directory'
complete -c hm -n '__fish_use_subcommand' -a profile -d 'Manage profiles and the active context'
complete -c hm -n '__fish_use_subcommand' -a add -d 'Register paths for the next generation'
complete -c hm -n '__fish_use_subcommand' -a gen -d 'Create a generation from the pending paths'
complete -c hm -n '__fish_use_subcommand' -a list -d 'Show generations, entries and pending paths'
complete -c hm -n '__fish_use_subcommand' -a status -d 'Show the project, the content store and every generation'
complete -c hm -n '__fish_use_subcommand' -a show -d 'Show the metadata and the entries of a generation'
complete -c hm -n '__fish_use_subcommand' -a diff -d 'Compare the entries of two or more generations'
complete -c hm -n '__fish_use_subcommand' -a edit -d 'Change the name and the comment of a generation'
complete -c hm -n '__fish_use_subcommand' -a switch -d 'Select a generation and materialize it in current/'
complete -c hm -n '__fish_use_subcommand' -a delete -d 'Delete a generation that is not selected'
complete -c hm -n '__fish_use_subcommand' -a apply -d 'Apply a generation to the tracked live paths'
complete -c hm -n '__fish_use_subcommand' -a discard -d 'Reset the testing workspace from current/'
complete -c hm -n '__fish_use_subcommand' -a backup -d 'Create a consistent backup of the project state'
complete -c hm -n '__fish_use_subcommand' -a restore -d 'Restore a previously created backup'
complete -c hm -n '__fish_use_subcommand' -a clean -d 'Remove the unreferenced content objects'
complete -c hm -n '__fish_use_subcommand' -a help -d 'Show the usage of HM-Lite'
complete -c hm -n '__fish_use_subcommand' -l help -s h -d 'Show the usage of HM-Lite'
complete -c hm -n '__fish_use_subcommand' -l version -d 'Show the version of HM-Lite'

# profile
complete -c hm -n '__hm_is_command profile' -l help -s h -d 'Show the usage of the profile command'
complete -c hm -n '__hm_profile_subcommand_slot' -a 'create add list show use rename delete help' -d 'Profile subcommand'
complete -c hm -n '__hm_profile_slot create 1' -a '(__fish_complete_directories)' -d 'Root directory'
complete -c hm -n '__hm_profile_path_slot' -F -a '(__hm_tracked_paths)' -d 'Path to register'
complete -c hm -n '__hm_profile_slot show 0; or __hm_profile_slot use 0; or __hm_profile_slot delete 0' -a '(__hm_profile_names)' -d 'Profile name'
complete -c hm -n '__hm_profile_slot rename 0; or __hm_profile_slot rename 1' -a '(__hm_profile_names)' -d 'Profile name'
complete -c hm -n '__hm_profile_has_subcommand delete; or __hm_profile_has_subcommand rename' -l yes -s y -d 'Do not ask for a confirmation'
complete -c hm -n '__hm_profile_has_subcommand delete' -l force -d 'Delete the history as well'

# init
complete -c hm -n '__hm_is_command init' -l help -s h -d 'Show the usage of the command'

# add
complete -c hm -n '__hm_is_command add' -l help -s h -d 'Show the usage of the command'
complete -c hm -n '__hm_is_command add' -l profile -r -f -a '(__hm_profile_names)' -d 'Profile of the paths'
complete -c hm -n '__hm_is_command add' -F -a '(__hm_tracked_paths)' -d 'Path that the project tracks'

# gen
complete -c hm -n '__hm_is_command gen' -l help -s h -d 'Show the usage of the command'
complete -c hm -n '__hm_is_command gen' -l profile -r -f -a '(__hm_profile_names)' -d 'Profile of the generation'
complete -c hm -n '__hm_is_command gen' -l name -r -f -d 'Name of the generation'
complete -c hm -n '__hm_is_command gen' -l comment -r -f -d 'Comment of the generation'
complete -c hm -n '__hm_is_command gen' -l yes -s y -d 'Do not ask for a confirmation'

# list
complete -c hm -n '__hm_is_command list' -l help -s h -d 'Show the usage of the command'
complete -c hm -n '__hm_is_command list' -l profile -r -f -a '(__hm_profile_names)' -d 'Profile to show'
complete -c hm -n '__hm_is_command list' -l generation -r -f -a '(__hm_generation_ids)' -d 'Identifier of the generation'
complete -c hm -n '__hm_is_command list' -l pending -d 'Show the paths that are queued for the next generation'
complete -c hm -n '__hm_is_command list' -l paths -d 'Show the tracked paths'
complete -c hm -n '__hm_is_command list' -l store -d 'Show the statistics of the content store'

# switch
complete -c hm -n '__hm_is_command switch' -l help -s h -d 'Show the usage of the command'
complete -c hm -n '__hm_is_command switch' -l profile -r -f -a '(__hm_profile_names)' -d 'Profile of the generation'
complete -c hm -n '__hm_is_command switch; and __hm_positional_slot switch' -a '(__hm_generation_ids)' -d 'Identifier of the generation'

# status
complete -c hm -n '__hm_is_command status' -l help -s h -d 'Show the usage of the command'
complete -c hm -n '__hm_is_command status' -l profile -r -f -a '(__hm_profile_names)' -d 'Profile to show'

# show
complete -c hm -n '__hm_is_command show' -l help -s h -d 'Show the usage of the command'
complete -c hm -n '__hm_is_command show' -l profile -r -f -a '(__hm_profile_names)' -d 'Profile of the generation'
complete -c hm -n '__hm_is_command show; and __hm_positional_slot show' -a '(__hm_generation_ids)' -d 'Identifier of the generation'

# diff
complete -c hm -n '__hm_is_command diff' -l help -s h -d 'Show the usage of the command'
complete -c hm -n '__hm_is_command diff' -l profile -r -f -a '(__hm_profile_names)' -d 'Profile of the generations'
complete -c hm -n '__hm_is_command diff' -l all -d 'Show the entries that did not change'
complete -c hm -n '__hm_is_command diff' -a '(__hm_generation_ids)' -d 'Identifier of the generation'

# edit
complete -c hm -n '__hm_is_command edit' -l help -s h -d 'Show the usage of the command'
complete -c hm -n '__hm_is_command edit' -l profile -r -f -a '(__hm_profile_names)' -d 'Profile of the generation'
complete -c hm -n '__hm_is_command edit' -l name -r -f -d 'Name of the generation'
complete -c hm -n '__hm_is_command edit' -l comment -r -f -d 'Comment of the generation'
complete -c hm -n '__hm_is_command edit' -l clear-name -d 'Remove the name of the generation'
complete -c hm -n '__hm_is_command edit' -l clear-comment -d 'Remove the comment of the generation'
complete -c hm -n '__hm_is_command edit' -l yes -s y -d 'Do not ask for a confirmation'
complete -c hm -n '__hm_is_command edit; and __hm_positional_slot edit' -a '(__hm_generation_ids)' -d 'Identifier of the generation'

# delete
complete -c hm -n '__hm_is_command delete' -l help -s h -d 'Show the usage of the command'
complete -c hm -n '__hm_is_command delete' -l profile -r -f -a '(__hm_profile_names)' -d 'Profile of the generation'
complete -c hm -n '__hm_is_command delete' -l yes -s y -d 'Do not ask for a confirmation'
complete -c hm -n '__hm_is_command delete; and __hm_positional_slot delete' -a '(__hm_generation_ids)' -d 'Identifier of the generation'

# apply
complete -c hm -n '__hm_is_command apply' -l help -s h -d 'Show the usage of the command'
complete -c hm -n '__hm_is_command apply' -l profile -r -f -a '(__hm_profile_names)' -d 'Profile of the selection'
complete -c hm -n '__hm_is_command apply' -l dry-run -d 'Show what would be written'
complete -c hm -n '__hm_is_command apply' -l yes -s y -d 'Do not ask for a confirmation'
complete -c hm -n '__hm_is_command apply; and __hm_positional_slot apply' -a '(__hm_generation_ids)' -d 'Identifier of the generation'

# discard
complete -c hm -n '__hm_is_command discard' -l help -s h -d 'Show the usage of the command'

# backup
complete -c hm -n '__hm_is_command backup' -l help -s h -d 'Show the usage of the command'

# restore
complete -c hm -n '__hm_is_command restore' -l help -s h -d 'Show the usage of the command'
complete -c hm -n '__hm_is_command restore' -l yes -s y -d 'Do not ask for a confirmation'
complete -c hm -n '__hm_is_command restore; and __hm_positional_slot restore' -F -a '(__hm_backup_archives)' -d 'Backup archive of the project'

# clean
complete -c hm -n '__hm_is_command clean' -l help -s h -d 'Show the usage of the command'
complete -c hm -n '__hm_is_command clean' -l dry-run -d 'Show what would be removed'
complete -c hm -n '__hm_is_command clean' -l yes -s y -d 'Do not ask for a confirmation'
