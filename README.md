# dataRecovery

# Use Rufus (Windows) to create Kali Live USB with persistence

# Allocate ≥4GB persistence storage

sudo apt update && sudo apt full-upgrade -y
sudo apt install adb mtp-tools jmtpfs exfat-fuse exfat-utils tree -y

# Troubleshooting Tips

# If script fails:

# Manual Mount:

# Open Windows File Explorer

# Note drive letter (e.g., D:)

# In Kali terminal:

sudo mkdir /mnt/windows_backups
sudo mount -t ntfs-3g /dev/sdb1 /mnt/windows_backups # Replace sdb1 with your partition

# Force MTP Mode:

Edit script: change adb_backup to mtp_backup

# Update MTP ID:

Get phone ID:

lsusb | grep -i samsung # Replace with your brand
Add to /etc/udev/rules.d/51-android.rules

## This system gives you a "plug and backup" solution with hard copies stored directly on Windows - perfect for weekly maintenance!

# Part 2: Pre-requisite Setup

## Install Required Tools (One-time setup in Kali):

sudo apt install rclone python3-pip
pip3 install gphotos-sync

# Configure Google Access:

# Authenticate Google services

rclone config # Follow prompts to connect Google Drive
gphotos-sync --init # Follow authentication steps

# Part 4: Location History & Routes Extraction

# For your route history and location data:

# Export Location History:

# In Takeout: Select "Location History" → JSON format

# Process Location Data:

# Convert JSON to KML for Google Earth

sudo apt install gpsbabel
gpsbabel -i geojson -f LocationHistory.json -o kml -F locations.kml

# Generate travel map

python3 -m pip install pandas geopandas matplotlib
Create map_generator.py:

python
import pandas as pd
import matplotlib.pyplot as plt

df = pd.read_json('LocationHistory.json')
df = df[df['accuracy'] < 100] # Filter inaccurate points

plt.figure(figsize=(12,8))
plt.scatter(df['longitude'], df['latitude'], s=0.1, alpha=0.5)
plt.savefig('travel_map.png', dpi=300)

## Part 5: WhatsApp Backup Handling

## For encrypted WhatsApp backups from Google Drive:

# Decrypting Backups:

# Install decryption tool

git clone https://github.com/EliteAndroidApps/WhatsApp-Key-DB-Extractor.git

# Extract when needed (requires rooted phone for key)

python3 extract.py -i ~/backups/whatsapp_google/msgstore.db.crypt12

# Alternative: Local Database Backup:

# Add to phone backup section:

bash

# Backup WhatsApp databases even if not synced to cloud

adb pull /sdcard/WhatsApp/Databases/ "$BACKUP_DIR/whatsapp_local"
