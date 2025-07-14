#!/bin/bash

# Configuration
WIN_PARTITION="/mnt/windows_backups"  # Will mount Windows partition here
BACKUP_ROOT="$WIN_PARTITION/Phone_Backups"
BACKUP_DIR="$BACKUP_ROOT/backup_$(date +%Y%m%d_%H%M%S)"

# Create directories
mkdir -p "$BACKUP_DIR" "$BACKUP_DIR/photos" "$BACKUP_DIR/contacts" "$BACKUP_DIR/whatsapp"

# Mount Windows partition (NTFS/FAT32)
mount_win_partition() {
    sudo mkdir -p "$WIN_PARTITION"
    # Try common Windows partitions
    for DEV in /dev/sda* /dev/nvme0n1p*; do
        sudo mount -t ntfs-3g -o ro "$DEV" "$WIN_PARTITION" 2>/dev/null && return 0
        sudo mount -t exfat "$DEV" "$WIN_PARTITION" 2>/dev/null && return 0
        sudo mount -t vfat "$DEV" "$WIN_PARTITION" 2>/dev/null && return 0
    done
    echo "ERROR: Couldn't mount Windows partition!" >&2
    exit 1
}

# ADB Backup Method
adb_backup() {
    echo "=== STARTING ADB BACKUP ==="
    adb pull /sdcard/DCIM/ "$BACKUP_DIR/photos" 2>/dev/null
    adb pull /sdcard/Pictures/ "$BACKUP_DIR/photos" 2>/dev/null
    
    adb shell am start -t "text/vcard" -a android.intent.action.SEND -e android.intent.extra.TEXT contacts.vcf >/dev/null
    sleep 15
    adb pull /sdcard/contacts.vcf "$BACKUP_DIR/contacts" 2>/dev/null
    
    adb pull /sdcard/WhatsApp/ "$BACKUP_DIR/whatsapp" 2>/dev/null
}

# MTP Backup Method
mtp_backup() {
    echo "=== STARTING MTP BACKUP ==="
    PHONE_MOUNT="/tmp/phone_mount"
    mkdir -p "$PHONE_MOUNT"
    
    # Auto-detect and mount phone
    jmtpfs "$PHONE_MOUNT" 2>/dev/null
    
    # Copy critical folders
    cp -r "$PHONE_MOUNT/Internal shared storage/DCIM" "$BACKUP_DIR/photos" 2>/dev/null
    cp -r "$PHONE_MOUNT/Internal shared storage/Pictures" "$BACKUP_DIR/photos" 2>/dev/null
    cp "$PHONE_MOUNT/Internal shared storage/contacts.vcf" "$BACKUP_DIR/contacts" 2>/dev/null
    cp -r "$PHONE_MOUNT/Internal shared storage/WhatsApp" "$BACKUP_DIR/whatsapp" 2>/dev/null
    
    fusermount -u "$PHONE_MOUNT"
}

# Main execution
mount_win_partition

# Check USB debugging
if adb devices | grep -q "device$"; then
    adb_backup
else
    mtp_backup
fi

# Generate report
echo -e "\n\033[1;32mBACKUP COMPLETE!\033[0m"
echo "Location: $BACKUP_DIR"
echo "Contents:"
tree "$BACKUP_DIR" -L 2

# Cleanup
sudo umount "$WIN_PARTITION"
echo "Safe to remove devices"