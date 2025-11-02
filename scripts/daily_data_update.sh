#!/bin/bash
set -euo pipefail

# ============================================================================
# Project Chronos: Automated Daily Data Update
# Production-Grade - Dev Container Compatible
# ============================================================================

# Configuration
PROJECT_ROOT="/workspace"
LOG_DIR="${PROJECT_ROOT}/logs"
LOG_FILE="${LOG_DIR}/daily_update_$(date +%Y%m%d_%H%M%S).log"

# Ensure log directory exists
mkdir -p "${LOG_DIR}"

# Logging function
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# log "=========================================="
# log "Starting daily data update"
# log "=========================================="

# # Pre-Update Backup
# log "Creating pre-update backup..."
# if /workspace/scripts/backup_database.sh >> "$LOG_FILE" 2>&1; then
#     log "✅ Backup completed"
# else
#     log "⚠️ Backup failed - continuing anyway"
# fi

# Track failures
FAILED=0

# Update FRED Core Data
log "Updating FRED core economic data..."
if python ${PROJECT_ROOT}/src/scripts/ingest_fred.py \
    -s CPIAUCSL -s PCEPI -s CPILFESL \
    -s UNRATE -s PAYEMS -s CIVPART -s U6RATE \
    -s GDPC1 -s GDPDEF -s INDPRO \
    -s FEDFUNDS -s DGS10 -s DGS2 -s DGS3MO -s T10Y2Y -s MORTGAGE30US \
    -s BAA10Y -s AAA10Y \
    -s NAPM -s UMCSENT -s RSAFS \
    -s HOUST -s CSUSHPISA \
    -s M2SL -s WALCL -s AMBSL \
    -s DCOILWTICO -s GOLDAMGBD228NLBM -s DHHNGSP -s PPIACO \
    >> "$LOG_FILE" 2>&1; then
    log "✅ FRED core data updated"
else
    log "❌ FRED core data failed"
    FAILED=$((FAILED + 1))
fi

# Update FRED FX Rates
log "Updating FRED FX rates..."
if python ${PROJECT_ROOT}/src/scripts/ingest_fred.py \
    -s DEXUSEU -s DEXUSUK -s DEXJPUS -s DEXCHUS -s DEXCAUS -s DEXMXUS \
    -s DEXUSAL -s DEXUSNZ -s DEXINUS -s DEXKOUS -s DEXBZUS -s DEXSFUS \
    >> "$LOG_FILE" 2>&1; then
    log "✅ FRED FX rates updated"
else
    log "❌ FRED FX rates failed"
    FAILED=$((FAILED + 1))
fi

# Update Bank of Canada Valet
log "Updating Bank of Canada Valet data..."
if python ${PROJECT_ROOT}/src/scripts/ingest_valet.py \
    -s V122530 -s V122485 -s V122487 -s V122486 -s V122531 \
    -s FXUSDCAD -s FXEURCAD -s FXGBPCAD -s FXJPYCAD -s FXCHFCAD \
    -s FXAUDCAD -s FXNZDCAD -s FXMXNCAD -s FXCNYCAD -s FXINRCAD \
    >> "$LOG_FILE" 2>&1; then
    log "✅ Valet data updated"
else
    log "❌ Valet data failed"
    FAILED=$((FAILED + 1))
fi

# Data Quality Check
log "Running data quality checks..."
psql -h chronos-db -U prometheus -d chronos_db << 'SQL' >> "$LOG_FILE" 2>&1
SELECT 
    freshness_status,
    COUNT(*) as series_count
FROM analytics.data_quality_dashboard
GROUP BY freshness_status
ORDER BY freshness_status;
SQL

# Cleanup old logs (keep 30 days)
find "${LOG_DIR}" -name "daily_update_*.log" -mtime +30 -delete 2>/dev/null || true

# Summary
log "=========================================="
if [ $FAILED -eq 0 ]; then
    log "✅ Daily update completed successfully!"
    log "=========================================="
    exit 0
else
    log "⚠️ Daily update completed with ${FAILED} failures"
    log "=========================================="
    exit 1
fi