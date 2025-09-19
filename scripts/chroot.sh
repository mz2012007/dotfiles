#!/usr/bin/env bash
sudo mount $1 $2 || {
  echo "Mount failed!"
  exit 1
}
sudo mount --bind /dev $2/dev
sudo mount --bind /proc $2/proc
sudo mount --bind /sys $2/sys
sudo mount --bind /dev/pts $2/dev/pts
sudo mount --bind /run $2/run
sudo mount --bind /var $2/var
sudo chroot --userspec=$3:$3 $2 /bin/bash
