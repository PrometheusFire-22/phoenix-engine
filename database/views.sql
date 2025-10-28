-- ============================================================================
-- Project Chronos: Data Quality and Normalization Views
-- ============================================================================
-- Purpose: Standardize raw data for analysis without modifying source data
-- Pattern: Raw → Normalized Views → Analytics
-- ============================================================================


-- ============================================================================
-- Create analytics schema if it doesn't exist (MUST BE FIRST!)
-- ============================================================================
CREATE SCHEMA IF NOT EXISTS analytics;

COMMENT ON SCHEMA analytics IS
'Normalized views and analytical queries.
Never stores data - always pulls from raw timeseries tables.';


-- ============================================================================
-- VIEW: FX Rates Normalized (All in USD per 1 Foreign Currency)
-- ============================================================================

CREATE OR REPLACE VIEW analytics.fx_rates_normalized AS
WITH raw_fx AS (
    SELECT 
        eo.observation_date,
        sm.source_series_id,
        eo.value as raw_value,
        sm.units,
        sm.geography
    FROM timeseries.economic_observations eo
    JOIN metadata.series_metadata sm ON eo.series_id = sm.series_id
    WHERE sm.source_series_id IN (
        'DEXUSEU',  -- EUR/USD
        'DEXUSUK',  -- GBP/USD
        'DEXCAUS',  -- CAD/USD (INVERTED)
        'DEXJPUS',  -- JPY/USD (if you add it)
        'DEXCHUS',  -- CNY/USD (if you add it)
        'FXUSDCAD'  -- Bank of Canada (CAD/USD, INVERTED)
    )
)
SELECT 
    observation_date,
    source_series_id,
    raw_value,
    geography,
    
    -- Standardized value: USD per 1 unit of foreign currency
    CASE 
        -- These are already USD per 1 FX (no transformation needed)
        WHEN source_series_id IN ('DEXUSEU', 'DEXUSUK') THEN raw_value
        
        -- These are FX per 1 USD (invert to get USD per 1 FX)
        WHEN source_series_id IN ('DEXCAUS', 'DEXJPUS', 'DEXCHUS', 'FXUSDCAD') 
            THEN 1.0 / NULLIF(raw_value, 0)
        
        ELSE raw_value  -- Default: no transformation
    END as usd_per_fx,
    
    -- Flag to indicate if value was inverted
    CASE 
        WHEN source_series_id IN ('DEXCAUS', 'FXUSDCAD') THEN TRUE
        ELSE FALSE
    END as was_inverted,
    
    -- Descriptive label
    CASE 
        WHEN source_series_id = 'DEXUSEU' THEN 'USD per EUR'
        WHEN source_series_id = 'DEXUSUK' THEN 'USD per GBP'
        WHEN source_series_id = 'DEXCAUS' THEN 'USD per CAD (inverted from raw)'
        WHEN source_series_id = 'FXUSDCAD' THEN 'USD per CAD (inverted from raw)'
        ELSE 'Unknown'
    END as rate_description
FROM raw_fx;

COMMENT ON VIEW analytics.fx_rates_normalized IS 
'Normalized FX rates: All values in USD per 1 unit of foreign currency.
Raw FRED data for DEXCAUS is CAD/USD and is inverted here for comparability.
Always use this view for cross-currency analysis.';

-- ============================================================================
-- VIEW: Macro Indicators Summary (Latest Values)
-- ============================================================================

CREATE OR REPLACE VIEW analytics.macro_indicators_latest AS
SELECT 
    sm.source_series_id,
    sm.series_name,
    sm.frequency,
    sm.units,
    sm.geography,
    lo.observation_date as latest_date,
    lo.value as latest_value,
    
    -- Add year-ago value for growth calculations
    LAG(lo.value, 
        CASE sm.frequency 
            WHEN 'D' THEN 365 
            WHEN 'M' THEN 12 
            WHEN 'Q' THEN 4 
            WHEN 'A' THEN 1 
            ELSE 1 
        END
    ) OVER (PARTITION BY sm.series_id ORDER BY lo.observation_date) as value_1y_ago,
    
    -- Calculate YoY growth
    ROUND(
        100.0 * (lo.value - LAG(lo.value, 4) OVER (PARTITION BY sm.series_id ORDER BY lo.observation_date)) 
        / NULLIF(LAG(lo.value, 4) OVER (PARTITION BY sm.series_id ORDER BY lo.observation_date), 0),
        2
    ) as yoy_growth_pct

FROM metadata.series_metadata sm
JOIN timeseries.latest_observations lo ON sm.series_id = lo.series_id
WHERE sm.is_active = TRUE;

COMMENT ON VIEW analytics.macro_indicators_latest IS
'Latest observation for each active series with year-over-year growth rates.
Use this for dashboard "current state" queries.';

-- ============================================================================
-- VIEW: Data Quality Dashboard
-- ============================================================================

CREATE OR REPLACE VIEW analytics.data_quality_dashboard AS
SELECT 
    ds.source_name,
    sm.source_series_id,
    sm.series_name,
    sm.frequency,
    
    -- Observation statistics
    COUNT(eo.observation_date) as total_observations,
    MIN(eo.observation_date) as earliest_date,
    MAX(eo.observation_date) as latest_date,
    MAX(eo.observation_date) - MIN(eo.observation_date) as date_span_days,
    
    -- Data quality metrics
    COUNT(CASE WHEN eo.value IS NULL THEN 1 END) as null_count,
    ROUND(100.0 * COUNT(CASE WHEN eo.value IS NULL THEN 1 END) / NULLIF(COUNT(*), 0), 2) as null_pct,
    
    -- Staleness check (days since last update)
    CURRENT_DATE - MAX(eo.observation_date) as days_since_last_update,
    
    CASE 
        WHEN CURRENT_DATE - MAX(eo.observation_date) > 7 THEN '🔴 STALE'
        WHEN CURRENT_DATE - MAX(eo.observation_date) > 3 THEN '🟡 WARNING'
        ELSE '🟢 FRESH'
    END as freshness_status

FROM metadata.series_metadata sm
JOIN metadata.data_sources ds ON sm.source_id = ds.source_id
LEFT JOIN timeseries.economic_observations eo ON sm.series_id = eo.series_id
WHERE sm.is_active = TRUE
GROUP BY ds.source_name, sm.source_series_id, sm.series_name, sm.frequency
ORDER BY days_since_last_update DESC;

COMMENT ON VIEW analytics.data_quality_dashboard IS
'Monitor data freshness, completeness, and coverage.
Use this for daily operational checks.';

-- ============================================================================
-- Create analytics schema if it doesn't exist
-- ============================================================================

CREATE SCHEMA IF NOT EXISTS analytics;

COMMENT ON SCHEMA analytics IS
'Normalized views and analytical queries.
Never stores data - always pulls from raw timeseries tables.';