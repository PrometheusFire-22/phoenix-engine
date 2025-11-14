#!/usr/bin/env bash

# ==============================================================================
#  Statistics Canada (StatCan) Bulk Downloader
# ==============================================================================
# Purpose:
#   Orchestrates the download of all 'Planned' national-level boundary files
#   for Canada from the 2021 Census, using our new ontology.
# ==============================================================================

set -e

# --- StatCan 2021 Boundary File URLs (English Shapefiles) ---
PROVINCES_URL="https://www12.statcan.gc.ca/census-recensement/2021/geo/sip-pis/boundary-limites/files-fichiers/lpr_000b21a_e.zip"
DIVISIONS_URL="https://www12.statcan.gc.ca/census-recensement/2021/geo/sip-pis/boundary-limites/files-fichiers/lcd_000b21a_e.zip"
SUBDIVISIONS_URL="https://www12.statcan.gc.ca/census-recensement/2021/geo/sip-pis/boundary-limites/files-fichiers/lcsd000b21a_e.zip"
CMA_URL="https://www12.statcan.gc.ca/census-recensement/2021/geo/sip-pis/boundary-limites/files-fichiers/lcma000b21a_e.zip"

echo "🚀 Starting bulk download of Statistics Canada national boundary files..."

# --- Call the generic downloader with the correct parameters ---
# Usage: ./scripts/download_shapefile.sh <URL> <country> <granularity> <layer_name>
./scripts/download_shapefile.sh "${PROVINCES_URL}" "CAN" "national" "lpr_000b21a_e"
./scripts/download_shapefile.sh "${DIVISIONS_URL}" "CAN" "national" "lcd_000b21a_e"
./scripts/download_shapefile.sh "${SUBDIVISIONS_URL}" "CAN" "national" "lcsd000b21a_e"
./scripts/download_shapefile.sh "${CMA_URL}" "CAN" "national" "lcma000b21a_e"

echo "✅ All Canadian national boundary files downloaded and organized."
