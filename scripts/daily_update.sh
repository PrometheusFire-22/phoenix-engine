#!/bin/bash
# ============================================================================
# Project Chronos: Daily Data Update Script
# ============================================================================
# Purpose: Automated daily ingestion from all sources
# Schedule: Run via cron at 6 AM EST (after markets open, before trading day)
# ============================================================================

set -e  # Exit on error

# Configuration
PROJECT_ROOT="/home/prometheus/coding/finance/project-chronos"
LOG_DIR="${PROJECT_ROOT}/logs"
LOG_FILE="${LOG_DIR}/daily_update_$(date +%Y%m%d).log"

# Ensure log directory exists
mkdir -p "${LOG_DIR}"

# Activate virtual environment
source "${PROJECT_ROOT}/venv/bin/activate"
export PYTHONPATH="${PYTHONPATH}:${PROJECT_ROOT}/src"

# Log start
echo "===============================================" | tee -a "${LOG_FILE}"
echo "Daily Update Started: $(date)" | tee -a "${LOG_FILE}"
echo "===============================================" | tee -a "${LOG_FILE}"

# Function to run ingestion with error handling
run_ingestion() {
    local source=$1
    local series=$2
    
    echo "" | tee -a "${LOG_FILE}"
    echo "Updating ${source}: ${series}" | tee -a "${LOG_FILE}"
    
    if python "${PROJECT_ROOT}/src/scripts/ingest_${source}.py" --series ${series} >> "${LOG_FILE}" 2>&1; then
        echo "✅ ${source} ${series} completed" | tee -a "${LOG_FILE}"
    else
        echo "❌ ${source} ${series} failed" | tee -a "${LOG_FILE}"
    fi
}

# ============================================================================
# Update FRED Series (U.S. Data)
# ============================================================================
echo "" | tee -a "${LOG_FILE}"
echo "--- FRED Updates ---" | tee -a "${LOG_FILE}"

# FX rates (daily)
run_ingestion "fred" "DEXUSEU"
run_ingestion "fred" "DEXUSUK"
run_ingestion "fred" "DEXCAUS"

# Economic indicators (various frequencies)
run_ingestion "fred" "FEDFUNDS"
run_ingestion "fred" "DGS10"

# Note: GDP, UNRATE, etc. are monthly/quarterly - update less frequently

# ============================================================================
# Update Bank of Canada Series
# ============================================================================
echo "" | tee -a "${LOG_FILE}"
echo "--- Bank of Canada Updates ---" | tee -a "${LOG_FILE}"

run_ingestion "valet" "FXUSDCAD FXEURCAD FXGBPCAD FXJPYCAD"

# ============================================================================
# Cleanup old logs (keep last 30 days)
# ============================================================================
find "${LOG_DIR}" -name "daily_update_*.log" -mtime +30 -delete

# Summary
echo "" | tee -a "${LOG_FILE}"
echo "===============================================" | tee -a "${LOG_FILE}"
echo "Daily Update Completed: $(date)" | tee -a "${LOG_FILE}"
echo "===============================================" | tee -a "${LOG_FILE}"

# Send notification (optional - uncomment if you set up email/slack)
# ./scripts/send_notification.sh "Daily Chronos update completed"