#!/usr/bin/env bash
# ==============================================================================
# Project Chronos: Bulk Ingestion Script for FRED Tier-1 Series
# ==============================================================================
#
# Usage: From the project root (/workspace), run:
#   bash scripts/bulk_ingest_fred.sh
#
# ==============================================================================

# Exit immediately if a command exits with a non-zero status.
set -e

# --- Configuration ---
# List of 22 core Tier-1 FRED series.
# Excludes Equities for now due to potential API access issues.
readonly FRED_SERIES_LIST=(
    # FX Rates
    DEXUSEU DEXUSUK DEXJPUS DEXCAUS DEXCHUS DEXMXUS DEXUSAL DEXUSNZ
    DEXINUS DEXKOUS DEXSZUS DEXTHUS
    # Interest Rates
    FEDFUNDS DFF DGS2 DGS5 DGS10 DGS30 MORTGAGE15US MORTGAGE30US
    # Inflation
    CPIAUCSL CPILFESL PCEPI PCEPILFE
    # Macro
    GDP GDPC1 UNRATE PAYEMS CIVPART INDPRO HOUST PERMIT RSXFS UMCSENT M2SL
    # Housing (for MVP POC)
    ATNHPIUS17031A MHIIL17031A052NCEN ILCOOK1URN ACTLISCOU17031 USSTHPI MEHOINUSA646N
)

# --- Script Body ---
echo "Constructing bulk ingestion command for ${#FRED_SERIES_LIST[@]} FRED series..."

# Base command
CMD="python src/scripts/ingest_fred.py"

# Append each series ID as a separate --series argument
for series in "${FRED_SERIES_LIST[@]}"; do
    CMD+=" --series $series"
done

# Execute the final command
echo "Executing..."
echo "----------------------------------------------------------------------"
eval $CMD
echo "----------------------------------------------------------------------"
echo "✅ FRED bulk ingestion command completed."
