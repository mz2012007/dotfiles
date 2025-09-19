#!/usr/bin/env bash
./cp.sh
cd ~/dotfiles
git add .
if [[ -z "$1" ]]; then
  git commit --amend --no-edit
  git push -f my main
  echo "well"
else
  git commit -m "$1"
  git push my main
  echo "changed"
fi
