#!/usr/bin/env bash
#sudo mount $1 $2 || {
#  echo "Mount failed!"
#  exit 1
#}
#sudo mount --bind /dev $2/dev
#sudo mount --bind /proc $2/proc
#sudo mount --bind /sys $2/sys
#sudo mount --bind /dev/pts $2/dev/pts
#sudo mount --bind /run $2/run
#sudo mount --bind /var $2/var
#sudo chroot --userspec=$3:$3 $2 /bin/bash

#!/usr/bin/env bash
#sudo mount $1 $2 || {
#  echo "Mount failed!"
#  exit 1
#}

#mount -t proc /proc $2/proc/
#mount -t sysfs /sys $2/sys/
#mount --rbind /dev $2/dev/
#mount --rbind /run $2/run/

#mount -B "$2" "$2"
#mount -i -o remount,suid "$2"

#sudo chroot --userspec=$3:$3 $2 /bin/bash

#lsof +D /mnt/sysroot
#umount -l
#umount -o bind

sudo mount --bind /dev $1/dev
sudo mount --bind /sys $1/sys
sudo mount --bind /proc $1/proc
sudo mount --bind /dev/pts $1/dev/pts
sudo mount --bind /sdcard $1/sdcard
sudo mount -i -o remount,suid $1

sudo chroot $1 /bin/su - root

#sudo umount $1/dev/pts
#sudo umount $1/dev
#sudo umount $1/proc
#sudo umount $1/sdcard
#sudo umount $1/sys
