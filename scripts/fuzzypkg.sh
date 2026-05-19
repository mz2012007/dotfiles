#!/usr/bin/env bash
SHELL="bash"
i() {
  local selection pkg
  local installed hold
  local choice idx=1
  local opt_install opt_remove opt_hold opt_unhold opt_cancel

  selection=$(
    xbps-query -Rs '' | awk '{print $2}' |
      fzf \
        --prompt='xbps> ' \
        --layout=reverse \
        --preview-window=right:65%:wrap \
        --bind 'ctrl-d:preview-half-page-down,ctrl-u:preview-half-page-up' \
        --preview '
          pkg=$(echo {} | sed "s/-[0-9].*$//")

          echo \"### STATUS ###\"

          if xbps-query \"\$pkg\" >/dev/null 2>&1; then
            echo \"INSTALLED\"
          else
            echo \"NOT INSTALLED\"
          fi

          if xbps-query -H 2>/dev/null | grep -q \"\$pkg\"; then
            echo \"HOLD: YES\"
          else
            echo \"HOLD: NO\"
          fi

          echo
          echo \"### INFO ###\"

          xbps-query -R \"\$pkg\" 2>/dev/null

          if ! xbps-query \"\$pkg\" >/dev/null 2>&1; then
            echo
            echo \"### INSTALL SIMULATION ###\"
            xbps-install -Svn \"\$pkg\" 2>/dev/null
          fi
          '
  )

  [ -z "$selection" ] && return

  pkg=$(echo "$selection" | sed 's/-[0-9].*$//')

  xbps-query "$pkg" >/dev/null 2>&1
  installed=$?

  xbps-query -H 2>/dev/null | grep -q "$pkg"
  hold=$?

  clear
  echo "Package : $pkg"
  echo "Status  : $([ $installed -eq 0 ] && echo INSTALLED || echo NOT INSTALLED)"
  echo "Hold    : $([ $hold -eq 0 ] && echo YES || echo NO)"
  echo

  if [ $installed -eq 0 ]; then
    echo "$idx) Remove"
    opt_remove=$idx
  else
    echo "$idx) Install"
    opt_install=$idx
  fi
  idx=$((idx + 1))

  if [ $hold -eq 0 ]; then
    echo "$idx) Unhold"
    opt_unhold=$idx
  else
    echo "$idx) Hold"
    opt_hold=$idx
  fi
  idx=$((idx + 1))

  echo "$idx) Cancel"
  opt_cancel=$idx

  read -rp "> " choice

  case "$choice" in
  "$opt_remove") sudo xbps-remove "$pkg" ;;
  "$opt_install") sudo xbps-install "$pkg" ;;
  "$opt_hold") sudo xbps-pkgdb -m hold "$pkg" ;;
  "$opt_unhold") sudo xbps-pkgdb -m unhold "$pkg" ;;
  "$opt_cancel") return ;;
  *) echo "Invalid choice" ;;
  esac
}
i
