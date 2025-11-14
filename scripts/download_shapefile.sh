#!/usr/bin/env bash

# ==============================================================================
#  Generic Shapefile Downloader (`download_shapefile.sh`)
# ==============================================================================
# Purpose:
#   A reusable utility to download a single zipped shapefile from a URL and
#   unzip it into the correct, ontology-driven directory structure.
#
# Geographic Ontology for <granularity>:
#   - 'national': For single files that cover the entire country.
#   - 'admin_1': For files split by the 1st-level admin division (state/province).
#
# Usage:
#   ./scripts/download_shapefile.sh <URL> <country_code> <granularity> <layer_name>
# ==============================================================================

set -e

if [ "$#" -ne 4 ]; then
    echo "❌ Error: Invalid number of arguments."
    echo "Usage: $0 <URL> <country_code> <granularity> <layer_name>"
    exit 1
fi

URL=$1
COUNTRY=$2
GRANULARITY=$3
LAYER_NAME=$4
FILENAME=$(basename "${URL}")

# --- Ontology-driven Directory and Path Construction ---
# Note: For admin_1 granularity, we group by layer first.
if [ "${GRANULARITY}" == "admin_1" ]; then
    ZIPPED_DIR="gis_data/raw/${COUNTRY}/${GRANULARITY}/${LAYER_NAME}/zipped"
    UNZIPPED_DIR="gis_data/raw/${COUNTRY}/${GRANULARITY}/${LAYER_NAME}/unzipped/${LAYER_NAME}"
else
    ZIPPED_DIR="gis_data/raw/${COUNTRY}/${GRANULARITY}/zipped"
    UNZIPPED_DIR="gis_data/raw/${COUNTRY}/${GRANULARITY}/unzipped/${LAYER_NAME}"
fi

mkdir -p "${ZIPPED_DIR}"
mkdir -p "${UNZIPPED_DIR}"

echo "▶️ Processing ${FILENAME} for ${COUNTRY}/${GRANULARITY}/${LAYER_NAME}..."
ZIPPED_FILE_PATH="${ZIPPED_DIR}/${FILENAME}"

if [ -f "$ZIPPED_FILE_PATH" ]; then
    echo "  - 🔵 Already downloaded. Skipping."
else
    echo "  - 🔽 Downloading from ${URL}..."
    wget -q -P "${ZIPPED_DIR}" "${URL}"
fi

if [ "$(ls -A ${UNZIPPED_DIR} 2>/dev/null)" ]; then
   echo "  - 🔵 Already unzipped. Skipping."
else
   echo "  - 📦 Unzipping to ${UNZIPPED_DIR}..."
   unzip -q -o "${ZIPPED_FILE_PATH}" -d "${UNZIPPED_DIR}"
fi

echo "✅ Success for ${LAYER_NAME}."
