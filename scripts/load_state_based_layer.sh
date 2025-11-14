#!/usr/bin/env bash

# ==============================================================================
#  Generic US Census State-Based Data Loader
# ==============================================================================
# Purpose:
#   Iterates through all US states and territories to load a specific
#   state-based shapefile layer (e.g., TRACT, PUMA) into a single,
#   unified nationwide table in PostGIS.
#
# Usage:
#   ./scripts/load_state_based_layer.sh <file_year> <layer_name> <table_name>
#
# Example (to load all 2024 Census Tracts):
#   ./scripts/load_state_based_layer.sh 2024 TRACT us_tracts
#
# Example (to load all 2020 PUMAs):
#   ./scripts/load_state_based_layer.sh 2020 PUMA20 us_pumas
# ==============================================================================

set -e

# --- 1. Input Validation ---
if [ "$#" -ne 3 ]; then
    echo "❌ Error: Invalid number of arguments."
    echo "Usage: $0 <file_year> <layer_name> <table_name>"
    echo "Example: $0 2024 TRACT us_tracts"
    exit 1
fi

# --- 2. Dynamic Variable Assignment ---
FILE_YEAR=$1
LAYER_UPPER=$2
TABLE_NAME=$3
LAYER_LOWER=$(echo "$LAYER_UPPER" | tr '[:upper:]' '[:lower:]')

# --- 3. Securely Load Environment Variables ---
if [ -f .env ]; then
  export $(grep -v '^#' .env | xargs)
else
  echo "❌ Error: .env file not found. This script requires a .env file for database credentials."
  exit 1
fi
PG_CONN_STRING="PG:host=${DATABASE_HOST} dbname=${DATABASE_NAME} user=${DATABASE_USER} password=${DATABASE_PASSWORD}"

# --- 4. The Complete List of US State & Territory FIPS Codes ---
FIPS_CODES=(
    "01" "02" "04" "05" "06" "08" "09" "10" "11" "12" "13" "15" "16" "17" "18"
    "19" "20" "21" "22" "23" "24" "25" "26" "27" "28" "29" "30" "31" "32" "33"
    "34" "35" "36" "37" "38" "39" "40" "41" "42" "44" "45" "46" "47" "48" "49"
    "50" "51" "53" "54" "55" "56" "60" "66" "69" "72" "78"
)

echo "▶️ Starting bulk ingestion of all US '${LAYER_UPPER}' layers for year ${FILE_YEAR}..."
echo "  - Destination Table: boundaries.${TABLE_NAME}"

# --- 5. The Ingestion Loop ---
FIRST_RUN=true
for fips in "${FIPS_CODES[@]}"; do
    LAYER_NAME="tl_${FILE_YEAR}_${fips}_${LAYER_LOWER}"
    SHAPEFILE_PATH="gis_data/raw/USA/state/${LAYER_UPPER}/unzipped/${LAYER_NAME}/${LAYER_NAME}.shp"

    if [ ! -f "$SHAPEFILE_PATH" ]; then
        echo "  - 🟡 Skipping FIPS ${fips}: Shapefile not found at expected path."
        continue
    fi

    echo "  - 🚚 Processing State FIPS: ${fips}"

    if [ "$FIRST_RUN" = true ]; then
        OGR_FLAGS="-overwrite"
        FIRST_RUN=false
    else
        OGR_FLAGS="-update -append"
    fi

    ogr2ogr \
      -f "PostgreSQL" \
      "${PG_CONN_STRING}" \
      "${SHAPEFILE_PATH}" \
      -nln "boundaries.${TABLE_NAME}" \
      -nlt "MULTIPOLYGON" \
      -lco GEOMETRY_NAME=geom \
      -t_srs EPSG:4269 \
      ${OGR_FLAGS} \
      -skipfailures
done

echo "✅ Success! All state data for '${LAYER_UPPER}' has been loaded into 'boundaries.${TABLE_NAME}'."
