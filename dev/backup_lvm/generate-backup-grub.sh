#!/usr/bin/env bash
set -e


BACKUP_DIR="$(mktemp -d /mnt/backup.XXXXXX)"                       # Base backup directory
GRUB_CUSTOM="/etc/grub.d/42_backup_boot"
LV="/dev/vg_main/lv_backup"
BOOT_DIR="/boot"



cleanup(){
  sudo umount $BACKUP_DIR
}





sudo mkdir -p $BACKUP_DIR
sudo mount $LV $BACKUP_DIR
echo "Generating GRUB entries..."

# ابدأ من أول وجديد
cat > "$GRUB_CUSTOM" <<'EOF'
#!/bin/sh
exec tail -n +3 $0
submenu "Backups" {
EOF

for TYPE in daily weekly monthly; do
    ROOT_DIR="$BACKUP_MOUNT/root/$TYPE"
    [ -d "$ROOT_DIR" ] || continue

    HAS_BACKUPS=false
    for DATE in $(ls -1 "$ROOT_DIR" 2>/dev/null | sort -r); do
        DATE_DIR="$ROOT_DIR/$DATE"
        [ -d "$DATE_DIR/boot" ] && [ "$(ls -1 "$DATE_DIR/boot/vmlinuz-"* 2>/dev/null | wc -l)" -gt 0 ] && HAS_BACKUPS=true && break
    done
    $HAS_BACKUPS || continue

    TITLE=$(echo "$TYPE" | sed 's/.*/\u&/')
    echo "    submenu \"$TITLE\" {" >> "$GRUB_CUSTOM"


    for DATE in $(ls -1 "$ROOT_DIR" | sort -r); do
        DATE_DIR="$ROOT_DIR/$DATE"
        KERNELS=( "$DATE_DIR/boot/vmlinuz-"* )
        [ -d "$DATE_DIR/boot" ] || continue
        [ -f "${KERNELS[0]}" ] || continue

        echo "        submenu \"$DATE\" {" >> "$GRUB_CUSTOM"


        for VMLINUZ in "${KERNELS[@]}"; do
            [ -f "$VMLINUZ" ] || continue
            KERNEL_FILE=$(basename "$VMLINUZ")
            GRUB_DATE_DIR="/root/$TYPE/$DATE"
            GRUB_VMLINUZ="$GRUB_DATE_DIR/boot/$KERNEL_FILE"

            INITRD_FILE=""
            for IR in "$DATE_DIR"/boot/initramfs-*.img; do
                if [[ "$IR" == "$DATE_DIR"/boot/initramfs-"${KERNEL_FILE#vmlinuz-}"* ]]; then
                    INITRD_FILE=$(basename "$IR")
                    break
                fi
            done
            [ -z "$INITRD_FILE" ] && continue

            UUID=$(blkid -s UUID -o value "$LV")
            cat >> "$GRUB_CUSTOM" <<EOF
            menuentry "$KERNEL_FILE" {
                load_video
                set gfxpayload=keep
                insmod gzio
                insmod part_msdos
                insmod lvm
                insmod ext2
                set root='lvm/vg_main-lv_backup'
                linux $GRUB_VMLINUZ root=$LV backup_type=$TYPE backup=$DATE rw
                initrd $GRUB_DATE_DIR/boot/$INITRD_FILE                
            }

EOF
        done

        echo "        }" >> "$GRUB_CUSTOM"
    done

    echo "    }" >> "$GRUB_CUSTOM"
done

echo "}" >> "$GRUB_CUSTOM"

chmod +x "$GRUB_CUSTOM"

trap cleanup SIGINT SIGTERM EXIT

echo "[*] Updating grub.cfg..."
grub-mkconfig -o /boot/grub/grub.cfg
echo "[*] GRUB backup entries updated successfully."
