#!/usr/bin/env bash
time=$(date +"%Y-%m-%d %I:%M:%S %p %a-%b-%y ")

sudo chronyc makestep
sudo hwclock --systohc --localtime
echo " time has been changed successfuly $time " >>/home/mz/fcronscripts/time/time.log

notify-send -i system-run " ✅ time has been rerighted successfuly  "
