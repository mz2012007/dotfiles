#!/usr/bin/env bash

sudo -v

while true; do
  sudo -v
  sleep 30
done &
SUDO_REFRESH_PID=$!

clear

# colors

RED="\e[31m"
GREEN="\e[32m"
YELLOW="\e[33m"
BLUE="\e[34m"
MAGENTA="\e[35m"
CYAN="\e[36m"
RESET="\e[0m"

#---------------------------------------------------------------------------------------------------

TMP_DIRS=()
trap 'for d in "${TMP_DIRS[@]}"; do rm -rf "$d"; done' EXIT

while true; do

  # all services

  echo -e "${MAGENTA}──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────${RESET}"
  echo " "
  echo -e "${BLUE}This is all services${RESET}"
  echo " "
  eza --color-scale-mode=gradient --icons /etc/sv/

  #---------------------------------------------------------------------------------------------------

  # enabled services

  echo -e "${MAGENTA}──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────${RESET}"
  echo " "
  echo -e "${GREEN}This is all services enabled${RESET}"
  echo " "
  eza --color-scale-mode=gradient --icons /var/service/

  #---------------------------------------------------------------------------------------------------

  # shutdown services

  shutdown_dir=$(mktemp -d)
  TMP_DIRS+=("$shutdown_dir")

  for s in /var/service/*; do
    service=$(basename "$s")
    status=$(sudo sv status "$service")
    if [[ $status == down* || $status == fail* ]]; then
      sudo mkdir "$shutdown_dir/$service"
    fi
  done

  echo -e "${MAGENTA}──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────${RESET}"
  echo " "
  echo -e "${RED}This services are shutdown${RESET}"
  echo " "

  if [ -z "$(ls -A $shutdown_dir 2>/dev/null)" ]; then
    echo -e "${YELLOW}No shutdown services found${RESET}"
  else
    eza --color-scale-mode=gradient --icons $shutdown_dir
  fi

  #---------------------------------------------------------------------------------------------------

  # up services

  n=$(comm -23 <(ls -1 /var/service/ | sort) <(ls -1 $shutdown_dir/ | sort))

  base=$(mktemp -d)
  TMP_DIRS+=("$base")

  for service in $n; do
    mkdir "$base/$service"
  done

  echo -e "${MAGENTA}──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────${RESET}"
  echo " "
  echo -e "${GREEN}These are up services${RESET}"
  echo " "

  eza --color-scale-mode=gradient --icons $base

  #---------------------------------------------------------------------------------------------------

  # disabled services

  m=$(comm -23 <(ls -1 /etc/sv/ | sort) <(ls -1 /var/service/ | sort))

  disabled_dir=$(mktemp -d)
  TMP_DIRS+=("$disabled_dir")

  for service in $m; do
    mkdir "$disabled_dir/$service"
  done

  echo -e "${MAGENTA}──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────${RESET}"
  echo ""
  echo -e "${RED}Disabled services: ${RESET}"
  echo ""

  if [ -z "$(ls -A $disabled_dir 2>/dev/null)" ]; then
    echo -e "${YELLOW}No disabled services found${RESET}"
  else
    eza --color-scale-mode=gradient --icons $disabled_dir
  fi

  #---------------------------------------------------------------------------------------------------

  # number of services

  count_all=$(ls -1 /etc/sv | wc -l)
  count_enabled=$(ls -1 /var/service | wc -l)
  count_disabled=$(ls -1 $disabled_dir | wc -l)
  count_up=$(ls -1 $base | wc -l)
  count_shutdown=$(ls -1 $shutdown_dir | wc -l)

  echo -e "${MAGENTA}──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────${RESET}"
  echo ""
  echo -e "${BLUE}Total services: $count_all${RESET}"
  echo -e "${GREEN}Enabled: $count_enabled${RESET}"
  echo -e "${RED}Disabled: $count_disabled${RESET}"
  echo -e "${GREEN}UP: $count_up${RESET}"
  echo -e "${RED}shutdown: $count_shutdown${RESET}"

  #---------------------------------------------------------------------------------------------------

  echo -e "${MAGENTA}──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────${RESET}"
  echo ""
  echo -e "${BLUE}Options: ${RESET}"
  echo ""
  echo "  e = enable service"
  echo "  d = disable service"
  echo "  s = shutdown service"
  echo "  u = start service"
  echo "  r = restart service"
  echo "  q = quit"
  echo ""
  echo -e "${MAGENTA}──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────${RESET}"

  read -n 1 -p " : " option

  if [[ "$option" == "e" || "$option" == "d" || "$option" == "s" || "$option" == "u" || "$option" == "r" ]]; then

    echo ""
    echo -e "${CYAN}Select a service to manage:${RESET}"

    if [[ "$option" == "d" ]]; then
      dir="/var/service/"
    elif [[ "$option" == "s" || "$option" == "r" ]]; then
      dir="$base"
    elif [[ "$option" == "u" ]]; then
      dir="$shutdown_dir"
    else
      dir="$disabled_dir"
    fi

    if [ -z "$(ls -A "$dir" 2>/dev/null)" ]; then
      echo -e "${YELLOW}No services available for this action.${RESET}"
      sleep 2
      continue
    else
      service=$(ls -1 "$dir" | fzf --prompt="Select a service: " --height=20%)
    fi

    if [[ -z "$service" ]]; then
      echo -e "${YELLOW}No service selected, skipping...${RESET}"
      continue
    fi

    case $option in
    e) sudo ln -s "/etc/sv/$service" "/var/service/" && echo "$service has been enabled" ;;
    d) if [ -L "/var/service/$service" ]; then
      sudo unlink -- "/var/service/$service" && echo "$service has been disabled"
    else
      echo "$service is not a symlink in /var/service/, skipping..."
    fi ;;
    s) sudo sv shutdown $service && echo "$service has been shutdown" ;;
    u) sudo sv up $service && echo "$service has been started" ;;
    r) sudo sv restart $service && echo "$service has been restarted" ;;
    esac
    sleep 5
    sudo sv status $service

  elif [[ "$option" == "" ]]; then
    echo ""
  elif [[ "$option" == "q" ]]; then
    clear
    exit 0
  else
    echo ""
    echo " Wrong choice"

    echo ""
    echo -e "${YELLOW}click (Enter) to continue${RESET}"
    echo ""
    echo -e "${RED}write (q) to exit${RESET}"
    echo ""

    read -n 1 -p "" mz
    if [[ "$mz" == "q" ]]; then
      break
    fi
  fi

  clear

  rm -rf "$shutdown_dir" "$base" "$disabled_dir" 2>/dev/null
  unset option service shutdown_dir base disabled_dir n m

done
clear
