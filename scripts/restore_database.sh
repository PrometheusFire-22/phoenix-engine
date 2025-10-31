#!/bin/bash
set -euo pipefail

# ============================================================================
# Production-Grade PostgreSQL Restore Script
# ============================================================================

# Check if backup file was provided
if [ $# -eq 0 ]; then
    echo "Usage: $0 <backup_file.sql.gz>"
    echo ""
    echo "Available backups:"
    ls -lh ~/coding/finance/project-chronos/backups/daily/*.sql.gz 2>/dev/null | tail -10 || echo "No backups found"
    exit 1
fi

BACKUP_FILE="$1"
CONTAINER_NAME="chronos-db"
DB_NAME="chronos_db"
DB_USER="prometheus"

# Verify backup file exists
if [ ! -f "$BACKUP_FILE" ]; then
    echo "ERROR: Backup file not found: $BACKUP_FILE"
    exit 1
fi

echo "WARNING: This will DROP and RECREATE the database!"
echo "Backup file: $BACKUP_FILE"
read -p "Are you sure? (type 'yes' to continue): " -r
if [ "$REPLY" != "yes" ]; then
    echo "Restore cancelled"
    exit 0
fi

echo "Decompressing backup..."
gunzip -c "$BACKUP_FILE" > /tmp/restore_temp.sql

echo "Dropping existing database..."
docker exec "$CONTAINER_NAME" psql -U "$DB_USER" -d postgres -c "DROP DATABASE IF EXISTS $DB_NAME;"

echo "Creating fresh database..."
docker exec "$CONTAINER_NAME" psql -U "$DB_USER" -d postgres -c "CREATE DATABASE $DB_NAME;"

echo "Restoring from backup..."
docker exec -i "$CONTAINER_NAME" psql -U "$DB_USER" -d "$DB_NAME" < /tmp/restore_temp.sql

echo "Cleaning up temporary files..."
rm /tmp/restore_temp.sql

echo "Restore completed successfully!"
echo "Verifying tables..."
docker exec "$CONTAINER_NAME" psql -U "$DB_USER" -d "$DB_NAME" -c "\dt"
