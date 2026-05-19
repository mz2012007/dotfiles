#!/usr/bin/env bash
set -e

# -----------------------------
# Configuration
# -----------------------------
BACKUP_DIR="/mnt/backup"
TMP_MOUNT="/mnt/snap"

VG_NAME="vg_main"
LV_BAK="lv_backup"

RETENTION_DAILY=7
RETENTION_WEEKLY=4
RETENTION_MONTHLY=6

declare -A PARTITIONS=(
  ["root"]="/dev/$VG_NAME/lv_root"
  ["home"]="/dev/$VG_NAME/lv_home"
  ["var"]="/dev/$VG_NAME/lv_var"
)

TS=$(date +"%a-%b_%d-%m-%Y_%I:%M:%S%p")

sudo modprobe dm_snapshot

# -----------------------------
# Cleanup
# -----------------------------
cleanup() {
    echo "[cleanup] Triggered"

    while mountpoint -q "$TMP_MOUNT"; do
        sudo umount -l "$TMP_MOUNT" || true
      done

    while mountpoint -q "$BACKUP_DIR"; do
        sudo umount -l "$BACKUP_DIR" || true
      done


    if [[ -n "${SNAP_NAME:-}" ]]; then
        if sudo lvdisplay "/dev/$VG_NAME/$SNAP_NAME" &>/dev/null; then
            sudo lvremove -f "/dev/$VG_NAME/$SNAP_NAME" || true
        fi
    fi
}

trap cleanup EXIT INT TERM

# -----------------------------
# Generate grub
# -----------------------------
generate(){
    echo "Generating grub config..."
    sudo /home/mz/dev/backup_lvm/generate-backup-grub
}

# -----------------------------
# Snapshot cleanup helper
# -----------------------------
cleanup_snapshot() {
    local snap="$1"

    echo "Removing snapshot $snap"

    if mountpoint -q "$TMP_MOUNT"; then
        sudo umount "$TMP_MOUNT"
    fi

    sudo lvremove -f "$snap"
}

# -----------------------------
# Retention
# -----------------------------
prune_retention() {

  local folder="$1"
  local count="$2"

  [[ ! -d "$folder" ]] && return

  mapfile -t backups < <(ls -1dl -c "$folder"/* 2>/dev/null | cut -d' ' -f10 || true)

  if (( ${#backups[@]} > count )); then
      for old in "${backups[@]:count}"; do
          echo "Pruning old backup: $old"
          sudo rm -rf "$old"
      done
  fi
}

# -----------------------------
# Weekly / Monthly rotation
# -----------------------------
rotate_special() {

  local name="$1"

  LAST_DAILY=$(ls -1dtr "$BACKUP_DIR/$name/daily/"* 2>/dev/null | tail -1 || true)
  [[ -z "$LAST_DAILY" ]] && return

  # Weekly (Sunday)
  if [[ "$(date +%u)" == "7" ]]; then
      DEST="$BACKUP_DIR/$name/weekly/$(basename "$LAST_DAILY")"
      echo "Creating weekly backup: $DEST"
      mkdir -p "$(dirname "$DEST")"
      cp -al "$LAST_DAILY" "$DEST"
  fi

  # Monthly (day 1)
  if [[ "$(date +%d)" == "01" ]]; then
      DEST="$BACKUP_DIR/$name/monthly/$(basename "$LAST_DAILY")"
      echo "Creating monthly backup: $DEST"
      mkdir -p "$(dirname "$DEST")"
      cp -al "$LAST_DAILY" "$DEST"
  fi
}

# -----------------------------
# Backup function
# -----------------------------
backup_partition() {

  local name="$1"
  local lv="$2"

  echo "Backing up $name ($lv)"

  SNAP_NAME="${name}_snap"

  sudo lvcreate -L 10G -s -n "$SNAP_NAME" "$lv"

  sudo mkdir -p "$TMP_MOUNT"
  sudo mount "/dev/$VG_NAME/$SNAP_NAME" "$TMP_MOUNT"

  DEST="$BACKUP_DIR/$name/daily/$TS"
  sudo mkdir -p "$DEST"

  LAST=$(ls -1dt "$BACKUP_DIR/$name/daily/"* 2>/dev/null | head -1 || true)


  RSYNC_CMD="sudo rsync -oarXHv --delete "
  RSYNC_CMD+=" --exclude=$BACKUP_DIR --exclude=$TMP_MOUNT --exclude=/etc/fstab"
  for b in "${LAST_BACKUPS[@]}"; do
    RSYNC_CMD+=" --link-dest=$BACKUP_DIR/$name/daily/$b" 
  done
  RSYNC_CMD+=" $TMP_MOUNT/ $DEST/" 

  echo "$RSYNC_CMD" echo "Running: $RSYNC_CMD"

  eval "$RSYNC_CMD"

  cleanup_snapshot "/dev/$VG_NAME/$SNAP_NAME"

  echo "Backup of $name completed"
}

# -----------------------------
# Prepare backup mount
# -----------------------------
sudo mkdir -p "$BACKUP_DIR"
sudo mount "/dev/$VG_NAME/$LV_BAK" "$BACKUP_DIR"

# -----------------------------
# Main backup loop
# -----------------------------
for part in "${!PARTITIONS[@]}"; do
  backup_partition "$part" "${PARTITIONS[$part]}"
  rotate_special "$part"
done

# -----------------------------
# Retention
# -----------------------------
for part in "${!PARTITIONS[@]}"; do
  prune_retention "$BACKUP_DIR/$part/daily" $RETENTION_DAILY
  prune_retention "$BACKUP_DIR/$part/weekly" $RETENTION_WEEKLY
  prune_retention "$BACKUP_DIR/$part/monthly" $RETENTION_MONTHLY
done

echo "Generating grub..."
generate

echo "All backups completed successfully."




create_dracut_backup_module() {
    local TYPE="$1"       # daily / weekly / monthly
    local DATE="$2"       # e.g. Sat-Mar_07-03-2026_10:13:47PM
    local readonly CHROOT="$(/mnt/chroot)"
    local BACKUP_DIR="$BACKUP_DIR"

    echo "[*] Creating dracut module for $TYPE $DATE"

    sudo mkdir -p "$CHROOT"
    
    # 1️⃣ Prepare chroot
    sudo mount --bind "$BACKUP_DIR/root/$TYPE/$DATE/" "$CHROOT"
    sudo mount --bind "$BACKUP_DIR/home/$TYPE/$DATE/" "$CHROOT/home"
    sudo mount --bind "$BACKUP_DIR/var/$TYPE/$DATE/"  "$CHROOT/var"
    sudo mount --rbind /dev/ "$CHROOT/dev/"
    sudo mount --rbind /proc/ "$CHROOT/proc/"
    sudo mount --rbind /sys/ "$CHROOT/sys/"

    # 2️⃣ Create dracut module
    MODDIR="$CHROOT/usr/lib/dracut/modules.d/90backup"
    sudo mkdir -p "$MODDIR"

    # module-setup.sh
    sudo tee "$MODDIR/module-setup.sh" >/dev/null <<'EOF'
#!/bin/bash
check() { return 0; }
depends() { return 0; }
install() {
    inst_hook pre-pivot 90 "$moddir/bind-backup.sh"
}
EOF
    sudo chmod +x "$MODDIR/module-setup.sh"

    # bind-backup.sh
    sudo tee "$MODDIR/bind-backup.sh" >/dev/null <<EOF
#!/bin/sh

PREREQ=""

prereqs() {
    echo "$PREREQ"
}

case $1 in
    prereqs)
        prereqs
        exit 0
        ;;
esac

# Read kernel parameters
for x in $(cat /proc/cmdline); do
    case $x in
        backup=*)
            BACKUP_DATE="${x#backup=}"
            ;;
        backup_type=*)
            BACKUP_TYPE="${x#backup_type=}"
            ;;
    esac
done

# Safety check
[ -z "$BACKUP_DATE" ] && exit 0
[ -z "$BACKUP_TYPE" ] && BACKUP_TYPE="daily"

mkdir -p /new_root

# mount backup LV
mount /dev/vg_main/lv_backup /new_root

BASE="$BACKUP_TYPE/$BACKUP_DATE"
NEWROOT="/new_root/root/$BASE"

if [ -d "$NEWROOT" ]; then
    echo "Booting backup: $NEWROOT"

    # optional bind mounts
    mount --bind "/new_root/home/$BASE" "$NEWROOT/home" 2>/dev/null
    mount --bind "/new_root/var/$BASE"  "$NEWROOT/var"  2>/dev/null

    echo "Switching root..."
    exec switch_root "$NEWROOT" /sbin/init
else
    echo "Backup not found: $NEWROOT"
fi    
EOF
    sudo chmod +x "$MODDIR/bind-backup.sh"

    # 3️⃣ Generate initramfs
    sudo chroot "$CHROOT" dracut -f

    # 4️⃣ Cleanup mounts
    sudo umount -l "$CHROOT/dev" "$CHROOT/proc" "$CHROOT/sys" "$CHROOT/var" "$CHROOT/home" "$CHROOT" || true
    sudo umount -R $CHROOT || true

    echo "[*] Dracut module for $TYPE $DATE generated successfully"
}
# Example usage:
# create_dracut_backup_module daily "Sat-Mar_07-03-2026_10:13:47PM"

