#!/bin/bash
# ============================================================================
# Project Chronos: Daily Data Update Script
# ============================================================================

set -e
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
LOG_DIR="${PROJECT_ROOT}/logs"
LOG_FILE="${LOG_DIR}/daily_update_$(date +%Y%m%d_%H%M%S).log"

mkdir -p "${LOG_DIR}"
cd "${PROJECT_ROOT}"

# Activate virtual environment (try both .venv and venv)
if [ -f ".venv/bin/activate" ]; then
    source .venv/bin/activate
elif [ -f "venv/bin/activate" ]; then
    source venv/bin/activate
else
    echo "ERROR: No virtual environment found"
    exit 1
fi

# Set PYTHONPATH
export PYTHONPATH="${PROJECT_ROOT}/src"

# Verify imports work
python -c "import chronos" || exit 1

# Logging functions
log_info() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1" | tee -a "${LOG_FILE}"
}

log_error() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1" | tee -a "${LOG_FILE}"
}

log_separator() {
    echo "============================================================" | tee -a "${LOG_FILE}"
}

# Start
log_separator
log_info "Daily update started"
log_separator

FAILED=0

# FRED FX Rates
log_info "Updating FRED FX rates..."
if python src/scripts/ingest_fred.py --series DEXUSEU --series DEXUSUK --series DEXCAUS >> "${LOG_FILE}" 2>&1; then
    log_info "✅ FRED FX completed"
else
    log_error "❌ FRED FX failed"
    FAILED=$((FAILED + 1))
fi

# FRED Interest Rates
log_info "Updating FRED interest rates..."
if python src/scripts/ingest_fred.py --series FEDFUNDS --series DGS10 >> "${LOG_FILE}" 2>&1; then
    log_info "✅ FRED rates completed"
else
    log_error "❌ FRED rates failed"
    FAILED=$((FAILED + 1))
fi

# Bank of Canada
log_info "Updating Bank of Canada..."
if python src/scripts/ingest_valet.py --series FXUSDCAD --series FXEURCAD --series FXGBPCAD --series FXJPYCAD >> "${LOG_FILE}" 2>&1; then
    log_info "✅ Valet completed"
else
    log_error "❌ Valet failed"
    FAILED=$((FAILED + 1))
fi

# Monthly updates (1st of month)
if [ $(date +%d) -eq 01 ]; then
    log_info "Running monthly updates..."
    if python src/scripts/ingest_fred.py --series GDP --series UNRATE --series CPIAUCSL >> "${LOG_FILE}" 2>&1; then
        log_info "✅ Monthly completed"
    else
        log_error "❌ Monthly failed"
        FAILED=$((FAILED + 1))
    fi
fi

# Cleanup old logs
find "${LOG_DIR}" -name "daily_update_*.log" -mtime +30 -delete 2>/dev/null || true

# Summary
log_separator
if [ $FAILED -eq 0 ]; then
    log_info "✅ All updates successful"
    exit 0
else
    log_error "⚠️  ${FAILED} update(s) failed"
    exit 1
fi