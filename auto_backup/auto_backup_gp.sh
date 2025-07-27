#!/usr/bin/env bash

# AndroidBackup: Copia dual a partición de Windows y carpeta persistente en USB (autoarranque)
# Requiere: adb, jmtpfs, rsync, tree, ntfs-3g, exfat-utils (o exfatprogs), lsblk

set -euo pipefail
IFS=$'\n\t'

# ===== Configuración =====
SCRIPT_NAME="$(basename "$0")"
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"

# Directorios de destino
WIN_MOUNT="/mnt/windows_backup"
USB_MOUNT="${XDG_HOME_DIR:-$HOME}/Documents/backUps"
BACKUP_SUBDIR="Phone_Backups"

# Umbral mínimo de espacio libre (GB)
MIN_SPACE_GB=10

# Timeout exportación contactos (s)
CONTACTS_TIMEOUT=30

# Colores para logs
COLOR_INFO="\033[1;32m"
COLOR_ERROR="\033[1;31m"
COLOR_DEBUG="\033[1;34m"
COLOR_RESET="\033[0m"

# Modo debug (activar con -v)
DEBUG_MODE=false
if [[ ${1:-} == "-v" ]]; then
  DEBUG_MODE=true
fi

# Archivos de log
LOG_DIR="/tmp/${SCRIPT_NAME}_logs"
mkdir -p "$LOG_DIR"
exec > >(tee -a "$LOG_DIR/backup_${TIMESTAMP}.log") 2>&1

log()    { echo -e "${COLOR_INFO}[INFO]${COLOR_RESET} $*" | tee -a "$LOG_DIR/last_run.log"; }
errlog() { echo -e "${COLOR_ERROR}[ERROR]${COLOR_RESET} $*" | tee -a "$LOG_DIR/last_run.log" >&2; }
debug()  { $DEBUG_MODE && echo -e "${COLOR_DEBUG}[DEBUG]${COLOR_RESET} $*" | tee -a "$LOG_DIR/last_run.log"; }

# Verificar espacio libre
check_space() {
  local path=$1 req=$2
  local free_kb=$(df -k "$path" | awk 'NR==2{print $4}')
  local free_gb=$((free_kb/1048576))
  debug "Espacio libre en $path: ${free_gb}GB"
  (( free_gb >= req )) || return 1
  return 0
}

# Montar partición (solo para Windows)
mount_windows_partition() {
  sudo mkdir -p "$WIN_MOUNT"
  for dev in /dev/sda[0-9]* /dev/nvme0n1p[0-9]*; do
    fs=$(lsblk -no FSTYPE "$dev" 2>/dev/null || true)
    case "$fs" in
      ntfs|exfat|vfat)
        if sudo mount -o ro -t "$fs" "$dev" "$WIN_MOUNT" &>/dev/null; then
          log "Montada partición Windows: $dev en $WIN_MOUNT ($fs)"
          return 0
        fi
        ;;
    esac
  done
  return 1
}

# Crear directorios backup
prepare_backup_dir() {
  local base=$1
  local target="$base/$BACKUP_SUBDIR/backup_$TIMESTAMP"
  mkdir -p "$target"/{photos,contacts,whatsapp}
  echo "$target"
}

# Exportar contactos ADB
export_contacts() {
  local outdir=$1
  local remote="/sdcard/contacts.vcf"
  adb shell am start -a android.intent.action.SEND -t text/vcard --es android.intent.extra.STREAM "$remote" &>/dev/null || true
  local start=$(date +%s)
  while (( $(date +%s) - start < CONTACTS_TIMEOUT )); do
    if adb shell ls "$remote" &>/dev/null; then
      adb pull "$remote" "$outdir/contacts/contacts.vcf" &>/dev/null && return 0
    fi
    sleep 2
  done
  errlog "Tiempo excedido exportando contactos"
  return 1
}

# Backup por ADB
adb_backup() {
  log "Modo ADB detectado"
  adb pull /sdcard/DCIM/ "$1/photos" || errlog "Error copiando DCIM"
  adb pull /sdcard/Pictures/ "$1/photos" || errlog "Error copiando Pictures"
  export_contacts "$1"
  adb pull /sdcard/WhatsApp/ "$1/whatsapp" || errlog "Error copiando WhatsApp"
}

# Backup por MTP
mtp_backup() {
  log "Modo MTP detectado"
  local mountpt="/tmp/phone_mount"
  mkdir -p "$mountpt"
  if ! jmtpfs "$mountpt" &>/dev/null; then
    errlog "Fallo al montar MTP"
    return
  fi
  for p in "Internal shared storage/DCIM" "Internal storage/DCIM" "DCIM"; do
    if [ -d "$mountpt/$p" ]; then
      rsync -av --info=progress2 "$mountpt/$p/" "$1/photos/"
      break
    fi
  done
  for p in "Internal shared storage/Pictures" "Internal storage/Pictures" "Pictures"; do
    if [ -d "$mountpt/$p" ]; then
      rsync -av --info=progress2 "$mountpt/$p/" "$1/photos/"
      break
    fi
  done
  if [ -f "$mountpt/contacts.vcf" ]; then
    cp "$mountpt/contacts.vcf" "$1/contacts/" || errlog "No se pudo copiar contacts.vcf"
  fi
  if [ -d "$mountpt/WhatsApp" ]; then
    rsync -av --info=progress2 "$mountpt/WhatsApp/" "$1/whatsapp/"
  fi
  fusermount -u "$mountpt"
}

# ===== Principal =====
MAIN(){
  log "Iniciando $SCRIPT_NAME"

  for cmd in adb jmtpfs lsblk rsync tree; do
    command -v "$cmd" >/dev/null || { errlog "Falta comando $cmd"; exit 1; }
  done

  # Windows opcional
  if mount_windows_partition; then
    if check_space "$WIN_MOUNT" $MIN_SPACE_GB; then
      win_backup=$(prepare_backup_dir "$WIN_MOUNT")
      log "Destino Windows: $win_backup"
    else
      errlog "Espacio insuficiente en Windows"
    fi
  else
    errlog "No se detectó partición Windows"
  fi

  # USB obligatorio (persistente)
  mkdir -p "$USB_MOUNT"
  if check_space "$USB_MOUNT" $MIN_SPACE_GB; then
    usb_backup=$(prepare_backup_dir "$USB_MOUNT")
    log "Destino USB persistente: $usb_backup"
  else
    errlog "Espacio insuficiente en USB"
    exit 1
  fi

  # Selección de método
  mode="mtp"
  if adb devices | grep -q "device$"; then mode="adb"; fi
  for target in ${win_backup:-} "$usb_backup"; do
    if [ "$mode" = "adb" ]; then adb_backup "$target"; else mtp_backup "$target"; fi
  done

  log "¡Backup finalizado!"
  log "Copia Windows: ${win_backup:-ninguna}"
  log "Copia USB: $usb_backup"
  tree "$usb_backup" -L 2

  sudo umount "$WIN_MOUNT" 2>/dev/null || true
  log "Listo: puede retirar dispositivos"
}

MAIN "$@"
