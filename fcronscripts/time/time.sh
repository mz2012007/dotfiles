#!/usr/bin/env bash
time=$(date +"%d-%m-%y_%a-%b-%y_%I:%M:%S-%p ")

sudo chronyc makestep
sudo hwclock --systohc --localtime
echo " time has been changed successfuly $time " >>/home/mz/fcronscripts/time/time.log

notify-send -i system-run " ✅ time has been rerighted successfuly  "
