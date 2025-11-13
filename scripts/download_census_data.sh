#!/usr/bin/env bash

# ==============================================================================
#  US Census State-Based Data Downloader
# ==============================================================================
# Purpose:
#   Automates downloading and unzipping of state-based shapefiles from the
#   US Census Bureau into a clean, organized directory structure.
#
# Usage:
#   ./scripts/download_census_data.sh <file_year> <layer_name> [source_year]
#
# Example (Tracts):
#   ./scripts/download_census_data.sh 2024 TRACT
#
# Example (PUMAs - where source year differs):
#   ./scripts/download_census_data.sh 2020 PUMA20 2020
# ==============================================================================

set -e

# --- 1. Input Validation ---
if [[ "$#" -lt 2 || "$#" -gt 3 ]]; then
    echo "❌ Error: Invalid number of arguments."
    echo "Usage: $0 <file_year> <layer_name_in_url> [source_year_override]"
    echo "Example (Tracts): $0 2024 TRACT"
    echo "Example (PUMAs):  $0 2020 PUMA20 2020"
    exit 1
fi

# --- 2. Variable Assignment ---
FILE_YEAR=$1
LAYER_UPPER=$2
SOURCE_YEAR=${3:-$FILE_YEAR} # Use 3rd arg if provided, otherwise default to file_year

# Convert layer name to lowercase for the filename, as per Census pattern
LAYER_LOWER=$(echo "$LAYER_UPPER" | tr '[:upper:]' '[:lower:]')

# --- 3. Structure-Aware Directory & URL Definitions ---
BASE_URL="https://www2.census.gov/geo/tiger/TIGER${SOURCE_YEAR}/${LAYER_UPPER}"
ZIPPED_DIR="gis_data/raw/USA/state/${LAYER_UPPER}/zipped"
UNZIPPED_DIR="gis_data/raw/USA/state/${LAYER_UPPER}/unzipped"
mkdir -p "${ZIPPED_DIR}" "${UNZIPPED_DIR}"

# --- 4. The Complete List of US State & Territory FIPS Codes ---
FIPS_CODES=(
    "01" "02" "04" "05" "06" "08" "09" "10" "11" "12" "13" "15" "16" "17" "18"
    "19" "20" "21" "22" "23" "24" "25" "26" "27" "28" "29" "30" "31" "32" "33"
    "34" "35" "36" "37" "38" "39" "40" "41" "42" "44" "45" "46" "47" "48" "49"
    "50" "51" "53" "54" "55" "56" "60" "66" "69" "72" "78"
)

echo "▶️ Starting download for '${LAYER_UPPER}' files (File Year: ${FILE_YEAR}, Source Year: ${SOURCE_YEAR})..."

# --- 5. Download and Unzip Loop ---
for fips in "${FIPS_CODES[@]}"; do
    FILENAME="tl_${FILE_YEAR}_${fips}_${LAYER_LOWER}.zip"
    URL="${BASE_URL}/${FILENAME}"
    ZIPPED_FILE_PATH="${ZIPPED_DIR}/${FILENAME}"
    UNZIPPED_TARGET_DIR="${UNZIPPED_DIR}/tl_${FILE_YEAR}_${fips}_${LAYER_LOWER}"

    echo "  - Processing State FIPS: ${fips}..."

    if [ -f "$ZIPPED_FILE_PATH" ]; then
        echo "    - 🔵 Already downloaded. Skipping."
    else
        echo "    - 🔽 Downloading ${FILENAME}..."
        # Use wget with --fail to exit if the file isn't found, and remove -q for better feedback.
        if ! wget --spider -q "${URL}"; then
             echo "    - ❌ ERROR: Could not find file at ${URL}. Skipping."
             continue
        fi
        wget -P "${ZIPPED_DIR}" "${URL}"
    fi

    if [ -d "$UNZIPPED_TARGET_DIR" ]; then
        echo "    - 🔵 Already unzipped. Skipping."
    else
        echo "    - 📦 Unzipping..."
        unzip -o "${ZIPPED_FILE_PATH}" -d "${UNZIPPED_TARGET_DIR}"
    fi
done

echo "✅ Download process complete for '${LAYER_UPPER}'."
