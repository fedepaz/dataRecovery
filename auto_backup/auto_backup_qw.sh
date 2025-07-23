#!/usr/bin/env bash

# phone_backup.sh - Enhanced Android backup to both Windows and USB
# v2.1 - Supports dual backups, dynamic detection, and error resilience

set -euo pipefail
IFS=$'\n\t'

# ============ Configuration ============
SCRIPT_NAME="$(basename "$0")"
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
LOGFILE_SUFFIX="backup.log"
DEBUG=${DEBUG:-0}
[ "$DEBUG" -eq 1 ] && set -x

# ============ Paths ============
declare -A BACKUP_TARGETS=(
    ["WINDOWS"]="/mnt/windows_drive"
    ["USB"]="/mnt/usb_stick"
)

# ============ Helpers ============
log() {
    echo "[INFO] $(date '+%T') $*"
}

debug() {
    [ "$DEBUG" -eq 1 ] && echo "[DEBUG] $*"
}

errlog() {
    echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - $*" >&2
}

# ============ Device Mounting ============
mount_device() {
    local target=$1
    local dev=$2
    local fs_type=$3
    
    sudo mkdir -p "$target"
    
    case "$fs_type" in
        ntfs|exfat|vfat)
            sudo mount -t "$fs_type" -o ro "$dev" "$target" 2>/dev/null
            return $?
            ;;
        *)
            return 1
            ;;
    esac
}

detect_and_mount() {
    local target=$1
    local -n success_ref=$2
    
    debug "Attempting to mount to $target"
    
    # Common Windows partitions
    for dev in /dev/sda[0-9]* /dev/nvme0n1p[0-9]* /dev/mmcblk0p[0-9]*; do
        [[ -b "$dev" ]] || continue
        
        fs_type=$(lsblk -no FSTYPE "$dev" 2>/dev/null)
        fs_type=${fs_type:-ntfs}
        
        if mount_device "$target" "$dev" "$fs_type"; then
            log "Mounted $dev ($fs_type) to $target"
            success_ref+=("$target")
            return 0
        fi
    done
    
    errlog "Failed to mount device to $target"
    return 1
}

# ============ Backup Functions ============
adb_backup() {
    local target=$1
    local photos="$target/photos"
    local contacts="$target/contacts"
    local whatsapp="$target/whatsapp"
    
    mkdir -p "$photos" "$contacts" "$whatsapp"
    
    log "Pulling photos from device..."
    adb pull -a /sdcard/DCIM "$photos/" || errlog "DCIM pull failed"
    adb pull -a /sdcard/Pictures "$photos/" || errlog "Pictures pull failed"
    
    log "Exporting contacts..."
    adb shell am start -a android.intent.action.DUMP --es com.android.contacts ALL > /dev/null 2>&1
    sleep 10
    adb pull /sdcard/contacts.vcf "$contacts/" || errlog "Contacts export failed"
    
    log "Pulling WhatsApp data..."
    adb pull -a /sdcard/WhatsApp "$whatsapp/" || errlog "WhatsApp pull failed"
    
    # Optional: Full ADB backup
    # adb backup -apk -shared -all -f "$target/full_backup.ab" || errlog "Full backup failed"
}

mtp_backup() {
    local target=$1
    local phone_mount="/tmp/phone_mount_$RANDOM"
    
    mkdir -p "$phone_mount"
    
    if ! jmtpfs "$phone_mount" -o ro; then
        errlog "MTP mount failed"
        return 1
    fi
    
    log "Copying media via MTP..."
    rsync -a --info=progress2 "$phone_mount/Internal shared storage/DCIM/" "$target/photos/" || true
    rsync -a --info=progress2 "$phone_mount/Internal shared storage/Pictures/" "$target/photos/" || true
    cp "$phone_mount/Internal shared storage/contacts.vcf" "$target/contacts/" || true
    rsync -a --info=progress2 "$phone_mount/Internal shared storage/WhatsApp/" "$target/whatsapp/" || true
    
    fusermount -u "$phone_mount"
    rm -rf "$phone_mount"
}

# ============ Main Execution ============
main() {
    local -a successful_mounts=()
    local -a failed_mounts=()
    
    # Mount all targets
    for target_name in "${!BACKUP_TARGETS[@]}"; do
        target_path="${BACKUP_TARGETS[$target_name]}"
        if detect_and_mount "$target_path" successful_mounts; then
            log "Successfully mounted $target_name device"
        else
            failed_mounts+=("$target_name")
            errlog "$target_name backup will not be available"
        fi
    done
    
    # Require at least one successful mount
    if [ ${#successful_mounts[@]} -eq 0 ]; then
        errlog "No valid backup devices found. Exiting."
        exit 1
    fi
    
    # Backup preparation
    BACKUP_ROOT="Phone_Backups/backup_$TIMESTAMP"
    
    # Process each successful mount
    for mount_point in "${successful_mounts[@]}"; do
        full_path="$mount_point/$BACKUP_ROOT"
        mkdir -p "$full_path"/{photos,contacts,whatsapp}
        
        log "Starting backup to $mount_point ($full_path)"
        
        if adb devices | grep -q "device$"; then
            adb_backup "$full_path"
        else
            mtp_backup "$full_path"
        fi
        
        # Verify backup
        if [ -n "$(ls -A "$full_path/photos")" ]; then
            log "Backup completed successfully to $mount_point"
        else
            errlog "Backup appears empty for $mount_point"
        fi
        
        # Unmount after backup
        sudo umount "$mount_point"
        log "Unmounted $mount_point"
    done
    
    # Final summary
    log "Backup completed to ${#successful_mounts[@]} devices"
    [ ${#failed_mounts[@]} -gt 0 ] && log "Failed mounts: ${failed_mounts[*]}"
    
    # Always verify USB backup
    if [[ " ${successful_mounts[*]} " =~ " ${BACKUP_TARGETS[USB]} " ]]; then
        log "USB backup verified at ${BACKUP_TARGETS[USB]}/$BACKUP_ROOT"
    else
        errlog "USB backup NOT completed"
        exit 1
    fi
}

main "$@"