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

# __hm_generation_ids
# Print the identifiers of the known generations, newest first. A missing or
# unreadable database is not an error, it produces no output. The database is
# opened read only, the file is never created and never modified.
function __hm_generation_ids
    set -l db (__hm_db_file)
    or return 0

    test -f $db; or return 0

    sqlite3 -readonly -noheader -list $db \
        'SELECT id FROM generations ORDER BY created_at DESC, id DESC;' 2>/dev/null
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

# ---------------------------------------------------------------------------
# The command surface
# ---------------------------------------------------------------------------

# __hm_positional_slot SUBCOMMAND
# Return 0 when the current token is the first positional argument of the
# subcommand. Options that are already typed are ignored, so
# "hm apply --dry-run <TAB>" still offers the generation identifiers.
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
            case --name --comment --generation
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
complete -c hm -n '__fish_use_subcommand' -a add -d 'Register paths for the next generation'
complete -c hm -n '__fish_use_subcommand' -a gen -d 'Create a generation from the pending paths'
complete -c hm -n '__fish_use_subcommand' -a list -d 'Show generations, entries and pending paths'
complete -c hm -n '__fish_use_subcommand' -a switch -d 'Select a generation and materialize it in current/'
complete -c hm -n '__fish_use_subcommand' -a apply -d 'Apply a generation to the tracked live paths'
complete -c hm -n '__fish_use_subcommand' -a discard -d 'Reset the testing workspace from current/'
complete -c hm -n '__fish_use_subcommand' -a backup -d 'Create a consistent backup of the project state'
complete -c hm -n '__fish_use_subcommand' -a restore -d 'Restore a previously created backup'
complete -c hm -n '__fish_use_subcommand' -a clean -d 'Remove the unreferenced content objects'
complete -c hm -n '__fish_use_subcommand' -a help -d 'Show the usage of HM-Lite'
complete -c hm -n '__fish_use_subcommand' -l help -s h -d 'Show the usage of HM-Lite'
complete -c hm -n '__fish_use_subcommand' -l version -d 'Show the version of HM-Lite'

# init
complete -c hm -n '__fish_seen_subcommand_from init' -l help -s h -d 'Show the usage of the command'

# add
complete -c hm -n '__fish_seen_subcommand_from add' -l help -s h -d 'Show the usage of the command'
complete -c hm -n '__fish_seen_subcommand_from add' -F -a '(__hm_tracked_paths)' -d 'Path that the project tracks'

# gen
complete -c hm -n '__fish_seen_subcommand_from gen' -l help -s h -d 'Show the usage of the command'
complete -c hm -n '__fish_seen_subcommand_from gen' -l name -r -f -d 'Name of the generation'
complete -c hm -n '__fish_seen_subcommand_from gen' -l comment -r -f -d 'Comment of the generation'
complete -c hm -n '__fish_seen_subcommand_from gen' -l yes -s y -d 'Do not ask for a confirmation'

# list
complete -c hm -n '__fish_seen_subcommand_from list' -l help -s h -d 'Show the usage of the command'
complete -c hm -n '__fish_seen_subcommand_from list' -l generation -r -f -a '(__hm_generation_ids)' -d 'Identifier of the generation'
complete -c hm -n '__fish_seen_subcommand_from list' -l pending -d 'Show the paths that are queued for the next generation'
complete -c hm -n '__fish_seen_subcommand_from list' -l paths -d 'Show the tracked paths'
complete -c hm -n '__fish_seen_subcommand_from list' -l store -d 'Show the statistics of the content store'

# switch
complete -c hm -n '__fish_seen_subcommand_from switch' -l help -s h -d 'Show the usage of the command'
complete -c hm -n '__fish_seen_subcommand_from switch; and __hm_positional_slot switch' -a '(__hm_generation_ids)' -d 'Identifier of the generation'

# apply
complete -c hm -n '__fish_seen_subcommand_from apply' -l help -s h -d 'Show the usage of the command'
complete -c hm -n '__fish_seen_subcommand_from apply' -l dry-run -d 'Show what would be written'
complete -c hm -n '__fish_seen_subcommand_from apply' -l yes -s y -d 'Do not ask for a confirmation'
complete -c hm -n '__fish_seen_subcommand_from apply; and __hm_positional_slot apply' -a '(__hm_generation_ids)' -d 'Identifier of the generation'

# discard
complete -c hm -n '__fish_seen_subcommand_from discard' -l help -s h -d 'Show the usage of the command'

# backup
complete -c hm -n '__fish_seen_subcommand_from backup' -l help -s h -d 'Show the usage of the command'

# restore
complete -c hm -n '__fish_seen_subcommand_from restore' -l help -s h -d 'Show the usage of the command'
complete -c hm -n '__fish_seen_subcommand_from restore' -l yes -s y -d 'Do not ask for a confirmation'
complete -c hm -n '__fish_seen_subcommand_from restore; and __hm_positional_slot restore' -F -a '(__hm_backup_archives)' -d 'Backup archive of the project'

# clean
complete -c hm -n '__fish_seen_subcommand_from clean' -l help -s h -d 'Show the usage of the command'
complete -c hm -n '__fish_seen_subcommand_from clean' -l dry-run -d 'Show what would be removed'
complete -c hm -n '__fish_seen_subcommand_from clean' -l yes -s y -d 'Do not ask for a confirmation'
