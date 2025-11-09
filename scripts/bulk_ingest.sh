#!/bin/bash
set -e

echo "🚀 Bulk ingesting FRED + Valet series..."

# FRED FX (10 more)
for series in DEXUSUK DEXJPUS DEXCAUS DEXCHUS DEXMXUS DEXUSAL DEXUSNZ DEXINUS DEXKOUS DEXSZUS; do
    echo "📊 FRED: $series"
    python src/scripts/ingest_fred.py --series $series
done

# FRED Interest Rates (8)
for series in FEDFUNDS DFF DGS2 DGS5 DGS10 DGS30 MORTGAGE15US MORTGAGE30US; do
    echo "📊 FRED: $series"
    python src/scripts/ingest_fred.py --series $series
done

# FRED Inflation (4)
for series in CPIAUCSL CPILFESL PCEPI PCEPILFE; do
    echo "📊 FRED: $series"
    python src/scripts/ingest_fred.py --series $series
done

# FRED Equities (5)
for series in SP500 DJIA NASDAQCOM WILL5000INDFC VIXCLS; do
    echo "📊 FRED: $series"
    python src/scripts/ingest_fred.py --series $series
done

# FRED Macro (11)
for series in GDP GDPC1 UNRATE PAYEMS CIVPART INDPRO HOUST PERMIT RSXFS UMCSENT M2SL; do
    echo "📊 FRED: $series"
    python src/scripts/ingest_fred.py --series $series
done

# Valet FX (9 more)
for series in FXEURCAD FXGBPCAD FXJPYCAD FXCHFCAD FXAUDCAD FXHKDCAD FXNZDCAD FXSEKCAD FXMXNCAD; do
    echo "📊 Valet: $series"
    python src/scripts/ingest_valet.py --series $series
done

# Valet Rates (6)
for series in V122530 V122531 V122514 V122515 V122487 V122488; do
    echo "📊 Valet: $series"
    python src/scripts/ingest_valet.py --series $series
done

# Valet Monetary (4)
for series in V41552796 V122495 V41552795 V41552794; do
    echo "📊 Valet: $series"
    python src/scripts/ingest_valet.py --series $series
done

echo "✅ Bulk ingestion complete!"
docker exec chronos-db psql -U prometheus -d chronos_db -c "
SELECT
    COUNT(DISTINCT series_id) as total_series,
    COUNT(*) as total_observations
FROM timeseries.economic_observations;
"
