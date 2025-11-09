#!/bin/bash
set -euo pipefail

echo "🚀 Project Chronos: Tier 1 Data Ingestion"
echo "=========================================="
echo ""

# FRED - U.S. Core (30 series)
echo "📊 Ingesting FRED Tier 1 (30 series)..."
python src/scripts/ingest_fred.py --series \
    CPIAUCSL PCEPI CPILFESL \
    UNRATE PAYEMS CIVPART U6RATE \
    GDPC1 GDPDEF INDPRO \
    FEDFUNDS DGS10 DGS2 DGS3MO T10Y2Y MORTGAGE30US \
    BAA10Y AAA10Y \
    NAPM UMCSENT RSAFS \
    HOUST CSUSHPISA \
    M2SL WALCL AMBSL \
    DCOILWTICO GOLDAMGBD228NLBM DHHNGSP PPIACO

echo ""
echo "📊 Ingesting FRED FX Rates (12 series)..."
python src/scripts/ingest_fred.py --series \
    DEXUSEU DEXUSUK DEXJPUS DEXCHUS DEXCAUS DEXMXUS \
    DEXUSAL DEXUSNZ DEXINUS DEXKOUS DEXBZUS DEXSFUS

echo ""
echo "📊 Ingesting Bank of Canada Valet (15 series)..."
python src/scripts/ingest_valet.py --series \
    V122530 V122485 V122487 V122486 V122531 \
    FXUSDCAD FXEURCAD FXGBPCAD FXJPYCAD FXCHFCAD \
    FXAUDCAD FXNZDCAD FXMXNCAD FXCNYCAD FXINRCAD

echo ""
echo "✅ Tier 1 ingestion complete!"
echo ""
echo "📊 Database Summary:"
psql -h chronos-db -U prometheus -d chronos_db -c "
SELECT
    'Series Registered' as metric,
    COUNT(*)::text as value
FROM metadata.series_metadata
UNION ALL
SELECT
    'Total Observations',
    COUNT(*)::text
FROM timeseries.economic_observations;
"
