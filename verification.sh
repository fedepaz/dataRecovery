# Verify critical data exists
check_files() {
    declare -a critical=(
        "$BACKUP_DIR/photos/DCIM"
        "$BACKUP_DIR/google_data/locations.kml"
        "$BACKUP_DIR/whatsapp_local/msgstore.db"
    )
    
    for file in "${critical[@]}"; do
        if [ -e "$file" ]; then
            echo "✓ $(basename "$file") exists"
        else
            echo "✗ MISSING: $(basename "$file")"
        fi
    done
}
check_files