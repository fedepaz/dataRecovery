#!/bin/bash

# ... [Previous setup code] ...

google_data_sync() {
    echo "=== SYNCING GOOGLE DATA ==="
    GOOGLE_DIR="$BACKUP_DIR/google_data"
    mkdir -p "$GOOGLE_DIR"
    
    # Google Takeout Manager
    echo "1. Requesting Google Takeout export..."
    xdg-open "https://takeout.google.com"  # Opens in browser
    
    # Google Drive Sync
    echo "2. Syncing Google Drive..."
    rclone config create gdrive drive config_is_local=false
    rclone copy gdrive: "$GOOGLE_DIR/gdrive" --progress
    
    # Google Photos Sync
    echo "3. Syncing Google Photos..."
    rclone copy gdrive:GooglePhotos "$GOOGLE_DIR/google_photos" --progress
    
    # WhatsApp Google Drive Backup
    echo "4. Downloading WhatsApp Backup..."
    rclone copy gdrive:/WhatsApp "$GOOGLE_DIR/whatsapp_google" --include "*.crypt12" --progress
}

# Main execution
mount_win_partition

# ... [Phone backup section] ...

google_data_sync

# ... [Report and cleanup] ...