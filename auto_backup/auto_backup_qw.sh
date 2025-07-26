#!/usr/bin/env bash

# phone_backup.sh - Respaldo Android a Windows y USB
# v2.2 - Soporta respaldos duales, detección dinámica y resiliencia

set -euo pipefail
IFS=$'\n\t'

# ============ Configuración ============
SCRIPT_NAME="$(basename "$0")"
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
LOGFILE_SUFFIX="respaldo.log"
DEBUG=${DEBUG:-0}
[ "$DEBUG" -eq 1 ] && set -x

# ============ Rutas ============
declare -A BACKUP_TARGETS=(
    ["WINDOWS"]="/mnt/windows_drive"
    ["USB"]="/root/android_backup"
)

# ============ Ayudantes ============
log() {
    echo "[INFO] $(date '+%T') $*"
}

debug() {
    [ "$DEBUG" -eq 1 ] && echo "[DEPURAR] $*"
}

errlog() {
    echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - $*" >&2
}

# ============ Montaje de Dispositivos ============
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
    
    debug "Intentando montar en $target"
    
    # Particiones Windows comunes
    for dev in /dev/sda[0-9]* /dev/nvme0n1p[0-9]* /dev/mmcblk0p[0-9]*; do
        [[ -b "$dev" ]] || continue
        
        fs_type=$(lsblk -no FSTYPE "$dev" 2>/dev/null)
        fs_type=${fs_type:-ntfs}
        
        if mount_device "$target" "$dev" "$fs_type"; then
            log "Montado $dev ($fs_type) en $target"
            success_ref+=("$target")
            return 0
        fi
    done
    
    errlog "No se pudo montar dispositivo en $target"
    return 1
}

# ============ Funciones de Respaldo ============
adb_backup() {
    local target=$1
    local photos="$target/fotos"
    local contacts="$target/contactos"
    local whatsapp="$target/whatsapp"
    
    mkdir -p "$photos" "$contacts" "$whatsapp"
    
    log "Extrayendo fotos del dispositivo..."
    adb pull -a /sdcard/DCIM "$photos/" || errlog "Fallo al extraer DCIM"
    adb pull -a /sdcard/Pictures "$photos/" || errlog "Fallo al extraer Imágenes"
    
    log "Exportando contactos..."
    adb shell am start -a android.intent.action.DUMP --es com.android.contacts ALL > /dev/null 2>&1
    sleep 10
    adb pull /sdcard/contacts.vcf "$contacts/" || errlog "Fallo al exportar contactos"
    
    log "Extrayendo datos de WhatsApp..."
    adb pull -a /sdcard/WhatsApp "$whatsapp/" || errlog "Fallo al extraer WhatsApp"
}

mtp_backup() {
    local target=$1
    local phone_mount="/tmp/phone_mount_$RANDOM"
    
    mkdir -p "$phone_mount"
    
    if ! jmtpfs "$phone_mount" -o ro; then
        errlog "Fallo al montar MTP"
        return 1
    fi
    
    log "Copiando multimedia vía MTP..."
    rsync -a --info=progress2 "$phone_mount/Internal shared storage/DCIM/" "$target/fotos/" || true
    rsync -a --info=progress2 "$phone_mount/Internal shared storage/Pictures/" "$target/fotos/" || true
    cp "$phone_mount/Internal shared storage/contacts.vcf" "$target/contactos/" || true
    rsync -a --info=progress2 "$phone_mount/Internal shared storage/WhatsApp/" "$target/whatsapp/" || true
    
    fusermount -u "$phone_mount"
    rm -rf "$phone_mount"
}

# ============ Ejecución Principal ============
main() {
    local -a successful_mounts=()
    local -a failed_mounts=()
    
    # Montar todos los objetivos
    for target_name in "${!BACKUP_TARGETS[@]}"; do
        target_path="${BACKUP_TARGETS[$target_name]}"
        if detect_and_mount "$target_path" successful_mounts; then
            log "¡$target_name montado correctamente!"
        else
            failed_mounts+=("$target_name")
            errlog "$target_name no estará disponible para respaldo"
        fi
    done
    
    # Requerir al menos un montaje exitoso
    if [ ${#successful_mounts[@]} -eq 0 ]; then
        errlog "No se encontraron dispositivos válidos. Saliendo."
        exit 1
    fi
    
    # Preparación del respaldo
    BACKUP_ROOT="Respaldo_Phone/backup_$TIMESTAMP"
    
    # Procesar cada montaje exitoso
    for mount_point in "${successful_mounts[@]}"; do
        full_path="$mount_point/$BACKUP_ROOT"
        mkdir -p "$full_path"/{fotos,contactos,whatsapp}
        
        log "Iniciando respaldo en $mount_point ($full_path)"
        
        if adb devices | grep -q "device$"; then
            adb_backup "$full_path"
        else
            mtp_backup "$full_path"
        fi
        
        # Verificar respaldo
        if [ -n "$(ls -A "$full_path/fotos")" ]; then
            log "¡Respaldo completado con éxito en $mount_point!"
        else
            errlog "El respaldo parece vacío en $mount_point"
        fi
        
        # Desmontar después del respaldo (solo para Windows)
        if [[ "$mount_point" == "/mnt/windows_drive" ]]; then
            sudo umount "$mount_point"
            log "Desmontado $mount_point"
        fi
    done
    
    # Resumen final
    log "Respaldo completado en ${#successful_mounts[@]} dispositivos"
    [ ${#failed_mounts[@]} -gt 0 ] && log "Dispositivos fallidos: ${failed_mounts[*]}"
    
    # Siempre verificar respaldo USB
    if [[ " ${successful_mounts[*]} " =~ " ${BACKUP_TARGETS[USB]} " ]]; then
        log "✅ ¡Respaldo USB verificado en ${BACKUP_TARGETS[USB]}/$BACKUP_ROOT!"
    else
        errlog "❌ ¡FALLO el respaldo USB!"
        exit 1
    fi
    
    log "¡Respaldo FINALIZADO con ÉXITO!"
    log "Puedes desconectar los dispositivos"
}

main "$@"