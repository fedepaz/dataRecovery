# 📱 Android Backup Script for Kali Linux

# auto_backup_qw.sh

A robust, dual-target backup solution for Android devices designed to run from Kali Linux Live USB. Safely backs up photos, contacts, and WhatsApp data to both Windows partitions and USB sticks.

---

## 📌 Features

✅ **Dual Backup Architecture**  
Backs up to both Windows and USB targets simultaneously

✅ **Automatic Detection**  
Supports dynamic detection of Windows partitions and USB devices

✅ **Flexible Connection Modes**  
Works with:

- ADB (USB Debugging enabled)
- MTP (File Transfer mode)

✅ **Safe & Reliable**

- Read-only mounts to prevent data corruption
- Verifies USB backup completion
- Detailed logging for troubleshooting

✅ **Portable**  
Runs from Kali Live USB on any laptop/desktop

---

## 🛠️ Requirements

Before using, ensure you have:

### Hardware

- Kali Linux Live USB (with persistence)
- Target devices:
  - Windows partition (NTFS/FAT32/exFAT)
  - Android device (USB cable)

### Software

Install dependencies with:

```bash
sudo apt install adb jmtpfs ntfs-3g exfat-fuse
```
