#!/usr/bin/env bash

sudo true

# colors

RED="\e[31m"
GREEN="\e[32m"
YELLOW="\e[33m"
BLUE="\e[34m"
MAGENTA="\e[35m"
CYAN="\e[36m"
RESET="\e[0m"

#---------------------------------------------------------------------------------------------------

# all services

echo " "
echo -e "${BLUE}This is all services${RESET}"
echo " "
eza --color-scale-mode=gradient --icons --hyperlink -AMHioF --total-size --show-symlinks /etc/sv/

#---------------------------------------------------------------------------------------------------

# enabled services

echo " "
echo -e "${GREEN}This is all services enabled${RESET}"
echo " "
eza --color-scale-mode=gradient --icons --hyperlink -AMHioF --total-size --show-symlinks /var/service/

#---------------------------------------------------------------------------------------------------

# shutdown services

base_dir=$(mktemp -d)

sudo chown -R $USER:$USER $base_dir

for s in /var/service/*; do
  service=$(basename "$s")
  status=$(sudo sv status "$service")
  if [[ $status == down* ]]; then
    sudo mkdir "$base_dir/$service"
  fi
done

echo " "
echo -e "${RED}This services are shutdown${RESET}"
echo " "

if [ -z "$(ls -A $base_dir 2>/dev/null)" ]; then
  echo -e "${YELLOW}No shutdown services found${RESET}"
else
  eza --color-scale-mode=gradient --icons --hyperlink -AMHioF --total-size --show-symlinks $base_dir
fi

#---------------------------------------------------------------------------------------------------

# up services

n=$(comm -23 <(ls -1 /var/service/ | sort) <(ls -1 $base_dir/ | sort))

base=$(mktemp -d)

trap "rm -rf $base_dir $base" EXIT

for service in $n; do
  mkdir "$base/$service"
done

echo " "
echo -e "${GREEN}These are up services${RESET}"
echo " "

eza --color-scale-mode=gradient --icons --hyperlink -AMHioF --total-size --show-symlinks $base

#---------------------------------------------------------------------------------------------------

# disabled services

m=$(comm -23 <(ls -1 /etc/sv/ | sort) <(ls -1 /var/service/ | sort))

for service in $m; do
  mkdir "$base_dir/$service"
done

echo ""
echo -e "${RED}Disabled services: ${RESET}"
echo ""

if [ -z "$(ls -A $base_dir 2>/dev/null)" ]; then
  echo -e "${YELLOW}No disabled services found${RESET}"
else
  eza --color-scale-mode=gradient --icons --hyperlink -AMHioF --total-size --show-symlinks $base_dir
fi

#---------------------------------------------------------------------------------------------------

echo ""
echo "Options:"
echo "  e = enable service"
echo "  d = disable service"
echo "  s = shutdown service"
echo "  u = start service"
echo "  r = restart service"
echo "  q = quit"
echo ""

read -p " : " option

if [[ "$option" == "e" || "$option" == "d" || "$option" == "s" || "$option" == "u" || "$option" == "r" ]]; then

  read -p "Service name: " services

  for service in $services; do

    if [[ -z "$service" ]]; then
      echo "Empty service name, skipping..."
      continue
    elif [[ ! -e "/etc/sv/$service" ]]; then
      echo "Service '$service' not found in /etc/sv/, skipping..."
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

    sudo sv status $service

  done

elif [[ "$option" == "q" ]]; then
  exit 0
else
  echo "Wrong choice"
fi
