# Update scripts/maintain_extensions.sh
#!/bin/bash
set -e

LOG_DIR="/workspace/logs"
LOG_FILE="${LOG_DIR}/extension_maint_$(date +%Y%m%d).log"

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log "Starting extension maintenance..."

# Reset pg_stat_statements (weekly)
if [ "$(date +%u)" -eq 1 ]; then  # Monday
    log "Weekly: Resetting pg_stat_statements"
    psql -h chronos-db -U prometheus -d chronos_db -c "SELECT pg_stat_statements_reset();"
fi

# Vacuum extension tables
log "Vacuuming extension tables..."
psql -h chronos-db -U prometheus -d chronos_db << SQL
VACUUM ANALYZE pg_stat_statements;
SQL

# Check graph size
log "Checking Apache AGE graph size..."
psql -h chronos-db -U prometheus -d chronos_db << SQL
SELECT pg_size_pretty(pg_database_size('chronos_db')) AS db_size;
SQL

log "✅ Extension maintenance complete"
