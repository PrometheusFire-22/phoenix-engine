#!/bin/bash
set -euo pipefail

# ============================================================================
# Production-Grade PostgreSQL Backup Script
# ============================================================================

# Configuration
BACKUP_DIR="/workspace/backups"
CONTAINER_NAME="chronos-db"
DB_NAME="chronos_db"
DB_USER="prometheus"
RETENTION_DAYS=30

# Timestamp
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="${BACKUP_DIR}/daily/chronos_db_${TIMESTAMP}.sql"
LOG_FILE="${BACKUP_DIR}/logs/backup_${TIMESTAMP}.log"

# Logging function
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log "Starting database backup..."

# Check if container is running
if ! docker ps | grep -q "$CONTAINER_NAME"; then
    log "ERROR: Container $CONTAINER_NAME is not running"
    exit 1
fi

# Perform backup
log "Running pg_dump..."
docker exec "$CONTAINER_NAME" pg_dump -U "$DB_USER" -d "$DB_NAME" \
    --format=plain \
    --no-owner \
    --no-acl \
    --verbose \
    > "$BACKUP_FILE" 2>> "$LOG_FILE"

# Verify backup file was created and is not empty
if [ ! -s "$BACKUP_FILE" ]; then
    log "ERROR: Backup file is empty or was not created"
    exit 1
fi

# Compress backup
log "Compressing backup..."
gzip "$BACKUP_FILE"
BACKUP_FILE="${BACKUP_FILE}.gz"

# Calculate and log backup size
BACKUP_SIZE=$(du -h "$BACKUP_FILE" | cut -f1)
log "Backup completed successfully: $BACKUP_FILE ($BACKUP_SIZE)"

# Clean up old backups
log "Cleaning up backups older than $RETENTION_DAYS days..."
find "${BACKUP_DIR}/daily" -name "*.sql.gz" -mtime +${RETENTION_DAYS} -delete
log "Cleanup completed"

# Verify backup integrity (decompress and check)
log "Verifying backup integrity..."
if gunzip -t "$BACKUP_FILE" 2>> "$LOG_FILE"; then
    log "Backup integrity verified successfully"
else
    log "ERROR: Backup file is corrupted"
    exit 1
fi

log "Backup process completed successfully"
