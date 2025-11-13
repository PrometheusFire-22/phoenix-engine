#!/usr/bin/env bash

# ==============================================================================
#  Geospatial Shapefile Loader (for Nationwide Layers)
# ==============================================================================
# Purpose:
#   A reusable script to load single, nationwide ESRI Shapefiles (.shp)
#   into the PostGIS database from the organized directory structure.
#
# Usage:
#   ./scripts/load_shapefile.sh <layer_name> <table_name>
#
# Example:
#   ./scripts/load_shapefile.sh tl_2024_us_state us_states
# ==============================================================================

set -e

# --- 1. Input Validation ---
if [ "$#" -ne 2 ]; then
    echo "❌ Error: Invalid number of arguments."
    echo "Usage: $0 <layer_name> <table_name>"
    echo "Example: $0 tl_2024_us_state us_states"
    exit 1
fi

# --- 2. Variable Assignment ---
LAYER_NAME=$1
TABLE_NAME=$2
SHAPEFILE_PATH="gis_data/raw/USA/national/unzipped/${LAYER_NAME}/${LAYER_NAME}.shp"

# --- 3. Pre-flight Check ---
if [ ! -f "$SHAPEFILE_PATH" ]; then
    echo "❌ Error: Shapefile not found at path: ${SHAPEFILE_PATH}"
    exit 1
fi

# --- 4. Securely Load Environment Variables ---
if [ -f .env ]; then
  export $(grep -v '^#' .env | xargs)
else
  echo "❌ Error: .env file not found. This script requires a .env file for database credentials."
  exit 1
fi
PG_CONN_STRING="PG:host=${DATABASE_HOST} dbname=${DATABASE_NAME} user=${DATABASE_USER} password=${DATABASE_PASSWORD}"

echo "▶️ Starting geospatial data ingestion..."
echo "  - Source Layer: ${LAYER_NAME}"
echo "  - Destination Table: boundaries.${TABLE_NAME}"

# --- 5. The `ogr2ogr` Command ---
ogr2ogr \
  -f "PostgreSQL" \
  "${PG_CONN_STRING}" \
  "${SHAPEFILE_PATH}" \
  -nln "boundaries.${TABLE_NAME}" \
  -nlt "MULTIPOLYGON" \
  -lco GEOMETRY_NAME=geom \
  -t_srs EPSG:4269 \
  -overwrite

echo "✅ Success! Data loaded into 'boundaries.${TABLE_NAME}'."
