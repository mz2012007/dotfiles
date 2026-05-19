#!/usr/bin/env bash
clear

option_conect_disconect=("Connect" "Disconnect")
option_Android_Iphone=("Android" "IPhone")

#read -n 1 -p "" option
option=$(printf '%s\n' "${option_conect_disconect[@]}" | fzf --prompt="Select Connect or Disconnect : " --height=20%)

case $option in

Connect)
  connect=$(printf '%s\n' "${option_Android_Iphone[@]}" | fzf --prompt="Select Android or IPhone: " --height=20%)
  case $connect in
  Android)
    mkdir -p ~/Android
    jmtpfs ~/Android
    ;;
  IPhone)
    mkdir -p ~/IPhone
    idevicepair pair
    ;;
  esac
  ;;

Disconnect)
  disconnect=$(printf '%s\n' "${option_Android_Iphone[@]}" | fzf --prompt="Select Android or IPhone: " --height=20%)
  case $diconnect in
  Android)
    sudo umount -R ~/Android
    ;;
  IPhone)
    sudo umount -R ~/IPhone
    ;;
  esac
  ;;
esac
