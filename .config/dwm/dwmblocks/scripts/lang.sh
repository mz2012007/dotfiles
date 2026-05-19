#!/usr/bin/env bash

lang=$(xkb-switch -p)

lang_change() {
  if [[ "$lang" == "ara" ]]; then
    xkb-switch -s us
    lang="us"
  else
    xkb-switch -s ara
    lang="ara"
  fi

}

case "$BLOCK_BUTTON" in
1) lang_change ;;
6) setsid -f "$TERMINAL" -e "$EDITOR" "$0" ;;
esac

case "$lang" in
us) bg="#5fafff" ;;
ara) bg="#af5fff" ;;
*) bg="#444444" ;;
esac

printf "^b#000000^^c%s^ ^c#ffffff^%s" "$bg" "$lang"
