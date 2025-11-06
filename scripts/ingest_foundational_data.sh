#!/bin/bash
set -e
echo "--- Starting Foundational Data Ingestion (Corrected) ---"

# --- 1. Ingest FRED Series ---
echo -e "\n[1/2] Ingesting data from FRED..."
python src/scripts/ingest_fred.py \
    --series GDP \
    --series GDPC1 \
    --series UNRATE \
    --series PAYEMS \
    --series JTSJOL \
    --series CPIAUCSL \
    --series PCE \
    --series PPIACO \
    --series FEDFUNDS \
    --series DGS10 \
    --series DGS2 \
    --series T10Y2Y \
    --series HOUST \
    --series MSPUS \
    --series UMCSENT \
    --series RETAILSM \
    --series INDPRO \
    --series ISM \
    --series M2SL \
    --series DEXUSEU \
    --series DEXUSUK \
    --series DEXJPUS \
    --series DEXUSCN

# --- 2. Ingest Valet Series ---
echo -e "\n[2/2] Ingesting data from Bank of Canada (Valet)..."
python src/scripts/ingest_valet.py \
    --series FXUSDCAD \
    --series FXEURCAD \
    --series FXGBPCAD \
    --series FXJPYCAD \
    --series FXAUDCAD \
    --series FXCNYCAD \
    --series V122513 \
    --series V122487 \
    --series V41690973 \
    --series V2062815 \
    --series V65201210

echo -e "\n--- Foundational Data Ingestion Complete ---"
