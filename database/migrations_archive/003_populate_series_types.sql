-- ============================================================================
-- Migration: Populate series_type for all series
-- Version: 003
-- Date: 2025-11-04
-- Description: Classify all 52 series into appropriate types based on
--              source_series_id patterns and economic categories
-- ============================================================================

BEGIN;

-- Foreign Exchange (FX) Rates
UPDATE metadata.series_metadata
SET series_type = 'FX'
WHERE source_series_id LIKE 'DEX%'
   OR source_series_id LIKE 'FX%'
   OR source_series_id LIKE 'DTWEX%';

-- Interest Rates
UPDATE metadata.series_metadata
SET series_type = 'Interest Rate'
WHERE source_series_id IN ('FEDFUNDS', 'DFF', 'MORTGAGE15US', 'MORTGAGE30US',
                           'V80691336', 'V80691337')
   OR source_series_id LIKE 'DGS%'
   OR source_series_id LIKE 'DTB%';

-- Inflation Indicators
UPDATE metadata.series_metadata
SET series_type = 'Inflation'
WHERE source_series_id LIKE '%CPI%'
   OR source_series_id LIKE '%PCE%';

-- Equity Indices
UPDATE metadata.series_metadata
SET series_type = 'Equity'
WHERE source_series_id IN ('SP500', 'DJIA', 'NASDAQCOM');

-- Commodities
UPDATE metadata.series_metadata
SET series_type = 'Commodity'
WHERE source_series_id LIKE 'DCOIL%'
   OR source_series_id = 'VIXCLS';

-- Monetary Aggregates
UPDATE metadata.series_metadata
SET series_type = 'Monetary'
WHERE source_series_id IN ('M2SL', 'WALCL', 'V122495', 'V41552796');

-- Housing Indicators
UPDATE metadata.series_metadata
SET series_type = 'Housing'
WHERE source_series_id IN ('HOUST', 'PERMIT');

-- Retail Sales
UPDATE metadata.series_metadata
SET series_type = 'Retail'
WHERE source_series_id = 'RSXFS';

-- Consumer Sentiment
UPDATE metadata.series_metadata
SET series_type = 'Sentiment'
WHERE source_series_id = 'UMCSENT';

-- Macroeconomic Indicators (catch-all for GDP, unemployment, employment, production)
UPDATE metadata.series_metadata
SET series_type = 'Macro'
WHERE source_series_id IN ('GDP', 'GDPC1', 'UNRATE', 'PAYEMS', 'CIVPART', 'INDPRO');

COMMIT;

-- Verification: Check classification results
SELECT
    CASE
        WHEN COUNT(*) FILTER (WHERE series_type IS NULL) > 0
        THEN 'WARNING: ' || COUNT(*) FILTER (WHERE series_type IS NULL) || ' series still NULL'
        ELSE 'SUCCESS: All ' || COUNT(*) || ' series classified'
    END AS status
FROM metadata.series_metadata;

-- ============================================================================
-- Verification Queries
-- ============================================================================
-- SELECT series_type, COUNT(*) as count
-- FROM metadata.series_metadata
-- GROUP BY series_type
-- ORDER BY series_type;

-- SELECT * FROM analytics.fx_rates_normalized LIMIT 10;
