#!/usr/bin/env bash

# colors

RED="\e[31m"
GREEN="\e[32m"
YELLOW="\e[33m"
BLUE="\e[34m"
MAGENTA="\e[35m"
CYAN="\e[36m"
RESET="\e[0m"

echo -e "
${GREEN} trash-empty   ${RESET}  ${BLUE}      empty the trashcan(s). ${RESET}
${GREEN} trash-list    ${RESET}  ${BLUE}      list trashed files. ${RESET}
${GREEN} trash-restore ${RESET}  ${BLUE}      restore a trashed file. ${RESET}
${GREEN} trash-rm      ${RESET}  ${BLUE}      remove individual files from the trashcan. ${RESET}
${GREEN} delete        ${RESET}  ${BLUE}      remove file. ${RESET}
"

if [ $# -eq 0 ]; then
  dir="$PWD"
else
  dir="$1"
fi

trash_dir="$HOME/.local/share/Trash/files/"

choices=("delete" "trash-list" "trash-restore" "trash-empty" "trash-rm")

option=$(printf '%s\n' "${choices[@]}" | fzf --prompt="Select Connect or Disconnect : " --height=20%)

case $option in
trash-list)
  trash-list
  ;;
trash-empty)
  trash-empty
  ;;
trash-restore)
  trash-restore
  ;;
trash-rm)
  if [ -n "$(ls -A "$trash_dir")" ]; then
    trashed_dir="$(ls -1 "$trash_dir" | fzf --prompt="Select a file: " --height=20%)"
    $trashed_dir
    if [ -z "$trashed_dir" ]; then
      echo " you didnot choiced "
      exit 0
    else
      gio trash $trashed_dir
    fi
  else
    echo "there is no trashed"
  fi
  ;;
delete)
  choised_dire="$(ls -1 "$dir" | fzf --prompt="Select a file: " --height=20%)"
  gio trash $choised_dire
  ;;
*)
  echo "No valid option selected."
  exit 0
  ;;
esac
