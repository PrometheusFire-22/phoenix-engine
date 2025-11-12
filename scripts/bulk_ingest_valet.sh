#!/usr/bin/env bash

# ==============================================================================
# Project Chronos: Bank of Canada Valet Bulk Ingestion Script
# ==============================================================================
# Purpose:
#   Performs the initial bulk ingestion of all Tier-1 Valet series.
#   This script is idempotent; it can be re-run without creating duplicates.
#
# Usage:
#   From the project root (/workspace):
#   ./scripts/bulk_ingest_valet.sh
# ==============================================================================

# Exit immediately if a command exits with a non-zero status.
set -e

# Ensure the script is run from the project root
cd "$(dirname "$0")/.."

echo "▶️ Starting Bank of Canada Valet Tier-1 Bulk Ingestion..."

# Define the list of core Valet series from the documentation
VALET_SERIES_LIST=(
    # FX Rates
    FXUSDCAD FXEURCAD FXGBPCAD FXJPYCAD FXCHFCAD FXAUDCAD
    # Interest Rates
    V122530 V122531 V122514 V122515
    # Monetary
    V41552796 V122495
)

# Build the arguments array for the Python script
ARGS=()
for series in "${VALET_SERIES_LIST[@]}"; do
    ARGS+=("--series" "$series")
done

# Execute the ingestion script
echo "📦 Ingesting ${#VALET_SERIES_LIST[@]} Valet series. This may take a few minutes..."
python src/scripts/ingest_valet.py "${ARGS[@]}"

echo "✅ Bank of Canada Valet Tier-1 Bulk Ingestion Complete."
