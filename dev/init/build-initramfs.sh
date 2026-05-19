#!/usr/bin/env bash

set -e


BACKUP_LV="/dev/vg_main/lv_backup"
readonly MOUNT_POINT="$(mktemp -d /mnt/mount.XXXXXX)"
readonly WORKDIR="$(mktemp -d /tmp/initramfs.XXXXXX)"
BOOTDIR="$ROOT_DIR/boot/"
ROOT_DIR="$MOUNT_POINT/root/daily/$TS"


KERNELS=()

# ------------------------------------------------------------------------------
# Mount and unmount backup
# ------------------------------------------------------------------------------
mount_backup() {
if mount | grep -q "$MOUNT_POINT"; then
    echo "[*] Backup already mounted"
    return
fi

sudo mkdir -p "$MOUNT_POINT"
echo "[*] Mounting backup LV"
sudo mount "$BACKUP_LV" "$MOUNT_POINT"
}

umount_backup() {
    echo "[*] Unmounting backup LV"
    sudo umount -R "$MOUNT_POINT" || true
}

# ------------------------------------------------------------------------------
# Extract kernel versions from backup /boot
# ------------------------------------------------------------------------------
extract_kernels() {
    echo "[*] Detecting kernels in $BOOTDIR"
    for k in "$BOOTDIR"/vmlinuz-*; do
        [ -f "$k" ] || continue
        KVER="${k##*/vmlinuz-}"
        KERNELS+=("$KVER")
    done
    echo "[*] Found kernels: ${KERNELS[*]}"
}

# ------------------------------------------------------------------------------
# Build initramfs for a given kernel
# ------------------------------------------------------------------------------
build_initramfs() {
    local KERNEL="$1"
    local ROOT_DIR="$MOUNT_POINT/root/daily/$TS"

    TS="$(sudo ls -1rt $MOUNT_POINT/root/daily/ | head -n 1)"
    echo "[*] Building initramfs for kernel $KERNEL"
    sudo mkdir -p "$WORKDIR"/{bin,sbin,dev,proc,sys,run,sysroot,lib/modules,scripts}

    # Copy essentials
    sudo cp $HOME/dev/init/initramfs-temp/bin/bash "$WORKDIR/bin/"
    sudo cp $HOME/dev/init/initramfs-temp/bin/busybox "$WORKDIR/bin/"

    # Install busybox applets
    sudo "$WORKDIR/bin/busybox" --install -s "$WORKDIR/bin/"
    sudo "$WORKDIR/bin/busybox" --install -s "$WORKDIR/sbin/"

    # Copy kernel modules for this kernel
    if [ -d "$ROOT_DIR/lib/modules/$KERNEL" ]; then
        sudo cp -r "$ROOT_DIR/lib/modules/$KERNEL" "$WORKDIR/lib/modules/"
    else
        echo "[!] Modules for $KERNEL not found, skipping."
        return
    fi

    # Copy init
    sudo cp $HOME/dev/init/initramfs-temp/init "$WORKDIR/init"
    sudo chmod +x "$WORKDIR/init"

    # Build initramfs with zstd
    cd "$WORKDIR"
    sudo find . | cpio -H newc -o | zstd -19 --threads=0 -o "$MOUNT_POINT/boot/initramfs-$KERNEL.img"

    echo "[+] Done initramfs for $KERNEL"
    sudo rm -rf "$WORKDIR"
}

cleanup (){
mountpoint -q "$MOUNT_POINT" && sudo umount -R "$MOUNT_POINT"
[ -d "$MOUNT_POINT" ] && sudo rm -rf "$MOUNT_POINT"

mountpoint -q "$WORKDIR" && sudo umount -R "$WORKDIR"
[ -d "$WORKDIR" ] && sudo rm -rf "$WORKDIR"

mountpoint -q "$BACKUP_LV" && sudo umount -R "$BACKUP_LV"

}
# ------------------------------------------------------------------------------
# Main flow
# ------------------------------------------------------------------------------
main() {
  mount_backup
  extract_kernels

  for KERNEL in "${KERNELS[@]}"; do
      build_initramfs "$KERNEL"
  done

  umount_backup
  trap cleanup SIGINT SIGTERM EXIT

}

main "$@"
