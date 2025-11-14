#!/usr/bin/env bash

# ==============================================================================
#  Geospatial Shapefile Loader (for Nationwide Layers)
# ==============================================================================
# Purpose:
#   A reusable script to load single, nationwide ESRI Shapefiles (.shp)
#   into PostGIS from the organized, ontology-driven directory structure.
#
# Usage:
#   ./scripts/load_shapefile.sh <country_code> <layer_name> <table_name>
#
# Example:
#   ./scripts/load_shapefile.sh USA tl_2024_us_state us_states
# ==============================================================================

set -e

if [ "$#" -ne 3 ]; then
    echo "❌ Error: Invalid number of arguments."
    echo "Usage: $0 <country_code> <layer_name> <table_name>"
    exit 1
fi

COUNTRY=$1
LAYER_NAME=$2
TABLE_NAME=$3
# Path is now constructed using the 'national' granularity from our ontology.
SHAPEFILE_PATH="gis_data/raw/${COUNTRY}/national/unzipped/${LAYER_NAME}/${LAYER_NAME}.shp"

if [ ! -f "$SHAPEFILE_PATH" ]; then
    echo "❌ Error: Shapefile not found at path: ${SHAPEFILE_PATH}"
    exit 1
fi

if [ -f .env ]; then
  export $(grep -v '^#' .env | xargs)
else
  echo "❌ Error: .env file not found."
  exit 1
fi
PG_CONN_STRING="PG:host=${DATABASE_HOST} dbname=${DATABASE_NAME} user=${DATABASE_USER} password=${DATABASE_PASSWORD}"

echo "▶️ Starting ingestion for nationwide layer: ${LAYER_NAME}..."
echo "  - Destination Table: boundaries.${TABLE_NAME}"

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
