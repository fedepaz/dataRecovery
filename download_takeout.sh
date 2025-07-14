#!/bin/bash
DOWNLOAD_URL="PASTE_EMAIL_LINK_HERE"
OUTPUT_DIR="$BACKUP_DIR/google_data/takeout"
mkdir -p "$OUTPUT_DIR"
wget -c "$DOWNLOAD_URL" -O "$OUTPUT_DIR/takeout_$(date +%F).zip"