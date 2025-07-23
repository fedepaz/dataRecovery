#!/usr/bin/env bash

# AndroidBackup: Dual backup to Windows partition and USB stick
# Requires: adb, jmtpfs, ntfs-3g, exfat-utils (or exfatprogs), vfat support, lsblk, rsync, tree

set -euo pipefail
IFS=$'\n\t'

# ===== Configuration =====
SCRIPT_NAME="$(basename "$0")"
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"

# Mount points
WIN_MOUNT="/mnt/windows_backup"
USB_MOUNT="/mnt/usb_backup"
BACKUP_SUBDIR="Phone_Backups"

# Free space thresholds (GB)
MIN_SPACE_GB=10

# Timeout for contact export (s)
CONTACTS_TIMEOUT=30

# ===== Helpers =====
log() { echo "[INFO] $*"; }
errlog() { echo "[ERROR] $*" >&2; }

# Check free space >= required GB
check_space() {
  local path=$1 req=$2 free_kb=$(df -k "$path" | awk 'NR==2{print $4}') free_gb=$((free_kb/1048576))
  (( free_gb >= req )) || return 1
  return 0
}

# Auto-detect & mount any partition by fs types
mount_partition() {
  local mount_point=$1
  sudo mkdir -p "$mount_point"
  for dev in /dev/sda[0-9]* /dev/nvme0n1p[0-9]* /dev/mmcblk0p[0-9]*; do
    fs=$(lsblk -no FSTYPE "$dev" 2>/dev/null) || continue
    case "$fs" in ntfs|exfat|vfat)
      if sudo mount -o ro "-t" "$fs" "$dev" "$mount_point" &>/dev/null; then
        log "Mounted $dev at $mount_point ($fs)"
        return 0
      fi
      ;;
    esac
  done
  return 1
}

# Prepare backup directory under a mount
prepare_backup_dir() {
  local base=$1 target="$base/$BACKUP_SUBDIR/backup_$TIMESTAMP"
  mkdir -p "$target"/{photos,contacts,whatsapp}
  echo "$target"
}

# Improved contact export via ADB
export_contacts() {
  local outdir=$1
  local remote="/sdcard/contacts.vcf"
  adb shell am start -a android.intent.action.SEND -t text/vcard --es android.intent.extra.STREAM "$remote" &>/dev/null || true
  local start=$(date +%s)
  while (( $(date +%s) - start < CONTACTS_TIMEOUT )); do
    if adb shell ls "$remote" &>/dev/null; then
      adb pull "$remote" "$outdir/contacts.vcf" &>/dev/null && return 0
    fi
    sleep 2
  done
  errlog "Contact export timed out"
  return 1
}

# Backup via ADB
adb_backup() {
  log "Using ADB backup"
  adb pull /sdcard/DCIM/ "$1/photos" || errlog "DCIM pull failed"
  adb pull /sdcard/Pictures/ "$1/photos" || errlog "Pictures pull failed"
  export_contacts "$1"
  adb pull /sdcard/WhatsApp/ "$1/whatsapp" || errlog "WhatsApp pull failed"
}

# Backup via MTP
mtp_backup() {
  log "Using MTP backup"
  local mountpt="/tmp/phone_mount"
  mkdir -p "$mountpt"
  jmtpfs "$mountpt" &>/dev/null || { errlog "MTP mount failed"; return; }

  # DCIM paths
  for p in "Internal shared storage/DCIM" "Internal storage/DCIM" "DCIM"; do
    if [ -d "$mountpt/$p" ]; then
      rsync -av --info=progress2 "$mountpt/$p/" "$1/photos/" && break
    fi
  done

  # Pictures
  for p in "Internal shared storage/Pictures" "Internal storage/Pictures" "Pictures"; do
    if [ -d "$mountpt/$p" ]; then
      rsync -av --info=progress2 "$mountpt/$p/" "$1/photos/" && break
    fi
  done

  # contacts.vcf
  if [ -f "$mountpt/contacts.vcf" ]; then
    cp "$mountpt/contacts.vcf" "$1/"contacts/ || errlog "contacts.vcf copy failed"
  fi

  # WhatsApp
  if [ -d "$mountpt/WhatsApp" ]; then
    rsync -av --info=progress2 "$mountpt/WhatsApp/" "$1/whatsapp/"
  fi

  fusermount -u "$mountpt"
}

# ===== Main =====
MAIN(){
  log "Starting $SCRIPT_NAME"
  # Dependencies check
  for cmd in adb jmtpfs lsblk rsync tree; do
    command -v "$cmd" >/dev/null || { errlog "Missing $cmd"; exit 1; }
  done

  # Mount Windows (optional)
  if mount_partition "$WIN_MOUNT"; then
    if check_space "$WIN_MOUNT" $MIN_SPACE_GB; then
      win_backup=$(prepare_backup_dir "$WIN_MOUNT")
      log "Backing up to Windows: $win_backup"
    else
      errlog "Not enough space on Windows mount"
    fi
  else
    errlog "Windows partition not found"
  fi

  # Mount USB (required)
  mount_partition "$USB_MOUNT" || { errlog "USB mount failed"; exit 1; }
  usb_backup=$(prepare_backup_dir "$USB_MOUNT")
  log "Backing up to USB: $usb_backup"

  # Choose ADB or MTP once and run both
  mode="mtpmode"
  if adb devices | grep -q "device$"; then mode="adbmode"; fi
  for target in ${win_backup:-} $usb_backup; do
    if [ "$mode" = "adbmode" ]; then adb_backup "$target"; else mtp_backup "$target"; fi
  done

  log "Backup complete!"
  log "Windows copy: ${win_backup:-none}"  
  log "USB copy: $usb_backup"
  tree "$USB_MOUNT/$BACKUP_SUBDIR/backup_$TIMESTAMP" -L 2

  # Unmount
  sudo umount "$WIN_MOUNT" 2>/dev/null || true
  sudo umount "$USB_MOUNT"
  log "Unmounted all and safe to remove devices"
}

MAIN "$@"
