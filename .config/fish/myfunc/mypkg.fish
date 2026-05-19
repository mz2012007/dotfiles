#!/usr/bin/env bash

function __mypkg_needs_command
    set -l cmd (commandline -opc)

    test (count $cmd) -eq 1
end

function __mypkg_using_command
    set -l cmd (commandline -opc)

    test (count $cmd) -ge 2
    and test $cmd[2] = $argv[1]
end

# Disable default file completion
complete -c mypkg -f

# =========================
# commands
# =========================

complete -c mypkg -n __mypkg_needs_command -a install -d "Install packages"
complete -c mypkg -n __mypkg_needs_command -a search -d "Search packages"
complete -c mypkg -n __mypkg_needs_command -a update -d "Update package database"

# =========================
# install options
# =========================

complete -c mypkg \
    -n '__mypkg_using_command install' \
    -l yes \
    -d "Auto confirm"

# install package names only
complete -c mypkg \
    -n '__mypkg_using_command install' \
    -a "(sqlite3 ./cache/mypkg.db 'select name from packages limit 200;')"

# =========================
# search package names only
# =========================

complete -c mypkg \
    -n '__mypkg_using_command search' \
    -a "(sqlite3 ./cache/mypkg.db 'select name from packages limit 200;')"

# =========================
# update options
# =========================

complete -c mypkg \
    -n '__mypkg_using_command update' \
    -l repo \
    -d "Repository name" \
    -r

complete -c mypkg \
    -n '__mypkg_using_command update' \
    -l arch \
    -d Architecture \
    -r
