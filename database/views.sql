-- ============================================================================
-- Project Chronos: Analytical Views and Data Quality Framework
-- ============================================================================
-- Version: 2.0
-- Purpose: Normalized views for analysis without modifying raw data
-- Last Updated: 2024-10-28
-- ============================================================================

-- ============================================================================
-- Create Analytics Schema
-- ============================================================================

CREATE SCHEMA IF NOT EXISTS analytics;

COMMENT ON SCHEMA analytics IS
'Normalized views and analytical queries.
Never stores data - always pulls from raw timeseries tables.
All views are safe to drop and recreate without data loss.';

-- ============================================================================
-- Drop existing views to allow clean recreation
-- ============================================================================

DROP VIEW IF EXISTS analytics.data_quality_dashboard CASCADE;
DROP VIEW IF EXISTS analytics.macro_indicators_latest CASCADE;
DROP VIEW IF EXISTS analytics.fx_rates_normalized CASCADE;

-- ============================================================================
-- VIEW 1: FX Rates Normalized
-- ============================================================================
-- Purpose: Standardize all FX rates to "USD per 1 unit of foreign currency"
-- Handles: FRED DEX* series and Bank of Canada FX* series
-- ============================================================================

CREATE VIEW analytics.fx_rates_normalized AS
WITH raw_fx AS (
    SELECT 
        eo.observation_date,
        sm.source_series_id,
        sm.series_id,
        eo.value as raw_value,
        sm.units,
        sm.geography,
        ds.source_name
    FROM timeseries.economic_observations eo
    JOIN metadata.series_metadata sm ON eo.series_id = sm.series_id
    JOIN metadata.data_sources ds ON sm.source_id = ds.source_id
    WHERE 
        -- Match ALL FX series using pattern matching
        (sm.source_series_id LIKE 'DEX%' OR sm.source_series_id LIKE 'FX%')
        AND eo.value IS NOT NULL
        AND eo.value != 0  -- Prevent division by zero
)
SELECT 
    observation_date,
    source_series_id,
    series_id,
    source_name,
    raw_value,
    geography,
    
    -- Standardized value: USD per 1 unit of foreign currency
    CASE 
        -- FRED: These are already USD per 1 FX (no transformation)
        WHEN source_series_id IN ('DEXUSEU', 'DEXUSUK', 'DEXUSAL') THEN raw_value
        
        -- FRED: These are FX per 1 USD (invert to get USD per FX)
        WHEN source_series_id LIKE 'DEXCA%'   -- DEXCAUS = CAD per USD
             OR source_series_id LIKE 'DEXJP%' -- DEXJPUS = JPY per USD
             OR source_series_id LIKE 'DEXCH%' -- DEXCHUS = CHF per USD
             OR source_series_id LIKE 'DEXMX%' -- DEXMXUS = MXN per USD
            THEN 1.0 / raw_value
        
        -- Bank of Canada: ALL FX* series are foreign currency per CAD
        -- To get USD per FX, we invert (this gives CAD per FX, then multiply by USD/CAD to get USD per FX)
        -- Simplified: For now, just invert to show relative strength
        WHEN source_series_id LIKE 'FX%' THEN 1.0 / raw_value
        
        -- Default: no transformation
        ELSE raw_value
    END as usd_per_fx,
    
    -- Flag if value was inverted
    CASE 
        WHEN source_series_id IN ('DEXCAUS', 'DEXJPUS', 'DEXCHUS', 'DEXMXUS') 
             OR source_series_id LIKE 'FX%' 
            THEN TRUE
        ELSE FALSE
    END as was_inverted,
    
    -- Human-readable description
    CASE 
        -- FRED series
        WHEN source_series_id = 'DEXUSEU' THEN 'USD per EUR (FRED)'
        WHEN source_series_id = 'DEXUSUK' THEN 'USD per GBP (FRED)'
        WHEN source_series_id = 'DEXUSAL' THEN 'USD per AUD (FRED)'
        WHEN source_series_id = 'DEXCAUS' THEN 'USD per CAD (FRED, inverted from raw)'
        WHEN source_series_id = 'DEXJPUS' THEN 'USD per JPY (FRED, inverted from raw)'
        WHEN source_series_id = 'DEXCHUS' THEN 'USD per CHF (FRED, inverted from raw)'
        WHEN source_series_id = 'DEXMXUS' THEN 'USD per MXN (FRED, inverted from raw)'
        
        -- Bank of Canada series
        WHEN source_series_id = 'FXUSDCAD' THEN 'USD per CAD (Bank of Canada, inverted from raw)'
        WHEN source_series_id = 'FXEURCAD' THEN 'EUR per CAD inverted (Bank of Canada)'
        WHEN source_series_id = 'FXGBPCAD' THEN 'GBP per CAD inverted (Bank of Canada)'
        WHEN source_series_id = 'FXJPYCAD' THEN 'JPY per CAD inverted (Bank of Canada)'
        
        -- Fallback for any other FX series
        ELSE 'FX rate: ' || source_series_id || ' (check raw value direction)'
    END as rate_description
FROM raw_fx;

COMMENT ON VIEW analytics.fx_rates_normalized IS 
'Normalized FX rates with consistent directionality.
TARGET: All values represent USD per 1 unit of foreign currency (where possible).

Transformation rules:
- FRED DEXUSEU/DEXUSUK: Already USD per FX (no change)
- FRED DEXCAUS/DEXJPUS: Raw is FX per USD → inverted to USD per FX
- Bank of Canada FX*: Raw is FX per CAD → inverted for consistency

Always use this view for cross-currency analysis.
Raw data remains unchanged in economic_observations table.';

-- ============================================================================
-- VIEW 2: Macro Indicators Latest (with Growth Calculations)
-- ============================================================================
-- Purpose: Show latest value for each series with year-over-year growth
-- ============================================================================

CREATE VIEW analytics.macro_indicators_latest AS
WITH ranked_obs AS (
    SELECT 
        sm.series_id,
        sm.source_series_id,
        sm.series_name,
        sm.frequency,
        sm.units,
        sm.geography,
        ds.source_name,
        eo.observation_date,
        eo.value,
        -- Rank observations by date (1 = most recent)
        ROW_NUMBER() OVER (PARTITION BY sm.series_id ORDER BY eo.observation_date DESC) as date_rank,
        -- Get value from 1 year ago based on frequency
        LAG(eo.value, 
            CASE sm.frequency 
                WHEN 'D' THEN 365 
                WHEN 'B' THEN 252  -- Business days
                WHEN 'W' THEN 52 
                WHEN 'M' THEN 12 
                WHEN 'Q' THEN 4 
                WHEN 'A' THEN 1 
                ELSE 12  -- Default to monthly
            END
        ) OVER (PARTITION BY sm.series_id ORDER BY eo.observation_date) as value_1y_ago
    FROM metadata.series_metadata sm
    JOIN metadata.data_sources ds ON sm.source_id = ds.source_id
    JOIN timeseries.economic_observations eo ON sm.series_id = eo.series_id
    WHERE sm.is_active = TRUE
)
SELECT 
    source_name,
    source_series_id,
    series_name,
    frequency,
    units,
    geography,
    observation_date as latest_date,
    value as latest_value,
    value_1y_ago,
    -- Calculate year-over-year growth percentage
    CASE 
        WHEN value_1y_ago IS NOT NULL AND value_1y_ago != 0 
        THEN ROUND(100.0 * (value - value_1y_ago) / value_1y_ago, 2)
        ELSE NULL
    END as yoy_growth_pct,
    -- Calculate absolute change
    CASE 
        WHEN value_1y_ago IS NOT NULL 
        THEN ROUND((value - value_1y_ago)::numeric, 2)
        ELSE NULL
    END as yoy_change_absolute
FROM ranked_obs
WHERE date_rank = 1;  -- Only latest observation

COMMENT ON VIEW analytics.macro_indicators_latest IS
'Latest observation for each active series with year-over-year calculations.
Automatically adjusts lookback period based on frequency:
- Daily/Business: 365/252 days
- Weekly: 52 weeks
- Monthly: 12 months
- Quarterly: 4 quarters
- Annual: 1 year

Use this for dashboard "current state" displays.';

-- ============================================================================
-- VIEW 3: Data Quality Dashboard (Frequency-Aware Staleness)
-- ============================================================================
-- Purpose: Monitor data freshness, completeness, and quality
-- Features: Frequency-aware staleness detection, null checking
-- ============================================================================

CREATE VIEW analytics.data_quality_dashboard AS
WITH series_stats AS (
    SELECT 
        sm.series_id,
        ds.source_name,
        sm.source_series_id,
        sm.series_name,
        sm.frequency,
        sm.geography,
        COUNT(eo.observation_date) as total_observations,
        MIN(eo.observation_date) as earliest_date,
        MAX(eo.observation_date) as latest_date,
        MAX(eo.observation_date) - MIN(eo.observation_date) as date_span_days,
        COUNT(CASE WHEN eo.value IS NULL THEN 1 END) as null_count,
        ROUND(100.0 * COUNT(CASE WHEN eo.value IS NULL THEN 1 END) / NULLIF(COUNT(*), 0), 2) as null_pct,
        CURRENT_DATE - MAX(eo.observation_date) as days_since_last_update
    FROM metadata.series_metadata sm
    JOIN metadata.data_sources ds ON sm.source_id = ds.source_id
    LEFT JOIN timeseries.economic_observations eo ON sm.series_id = eo.series_id
    WHERE sm.is_active = TRUE
    GROUP BY sm.series_id, ds.source_name, sm.source_series_id, sm.series_name, sm.frequency, sm.geography
),
staleness_rules AS (
    SELECT 
        *,
        -- Define frequency-specific staleness thresholds
        CASE 
            WHEN frequency = 'D' THEN 7       -- Daily: Max 7 days lag
            WHEN frequency = 'B' THEN 7       -- Business daily: Max 7 days lag
            WHEN frequency = 'W' THEN 14      -- Weekly: Max 14 days lag
            WHEN frequency = 'M' THEN 120     -- Monthly: Max 4 months lag
            WHEN frequency = 'Q' THEN 215     -- Quarterly: Max 7 months lag
            WHEN frequency = 'A' THEN 730     -- Annual: Max 2 years lag
            WHEN frequency IS NULL THEN 30    -- Unknown: Default 30 days
            ELSE 30
        END as max_acceptable_lag_days,
        
        -- Warning threshold (triggers before stale)
        CASE 
            WHEN frequency = 'D' THEN 3
            WHEN frequency = 'B' THEN 3
            WHEN frequency = 'W' THEN 7
            WHEN frequency = 'M' THEN 60
            WHEN frequency = 'Q' THEN 120
            WHEN frequency = 'A' THEN 365
            WHEN frequency IS NULL THEN 14
            ELSE 14
        END as warning_threshold_days
    FROM series_stats
)
SELECT 
    source_name,
    source_series_id,
    series_name,
    frequency,
    geography,
    total_observations,
    earliest_date,
    latest_date,
    date_span_days,
    null_count,
    null_pct,
    days_since_last_update,
    max_acceptable_lag_days,
    warning_threshold_days,
    
    -- Status indicator with frequency-aware logic
    CASE 
        WHEN days_since_last_update IS NULL THEN '⚪ NO DATA'
        WHEN days_since_last_update > max_acceptable_lag_days THEN '🔴 STALE'
        WHEN days_since_last_update > warning_threshold_days THEN '🟡 WARNING'
        ELSE '🟢 FRESH'
    END as freshness_status,
    
    -- Expected next update date
    CASE 
        WHEN latest_date IS NOT NULL 
        THEN latest_date + (max_acceptable_lag_days || ' days')::interval
        ELSE NULL
    END as expected_update_by,
    
    -- Days remaining until stale
    CASE 
        WHEN days_since_last_update IS NOT NULL
        THEN max_acceptable_lag_days - days_since_last_update
        ELSE NULL
    END as days_until_stale
    
FROM staleness_rules
ORDER BY 
    -- Sort by severity: stale → warning → fresh
    CASE 
        WHEN days_since_last_update IS NULL THEN 4
        WHEN days_since_last_update > max_acceptable_lag_days THEN 1
        WHEN days_since_last_update > warning_threshold_days THEN 2
        ELSE 3
    END,
    days_since_last_update DESC NULLS LAST;

COMMENT ON VIEW analytics.data_quality_dashboard IS
'Frequency-aware data quality monitoring dashboard.

Staleness Thresholds by Frequency:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Frequency │ Warning │ Stale  │ Rationale
──────────┼─────────┼────────┼─────────────────────────
Daily (D) │  3 days │ 7 days │ Daily data lags ~1-2 days
Business  │  3 days │ 7 days │ Business days only
Weekly    │  7 days │14 days │ Weekly releases lag ~1 week
Monthly   │ 60 days │120 days│ Monthly data lags 1-2 months
Quarterly │120 days │215 days│ GDP-style lags 3-4 months
Annual    │365 days │730 days│ Annual reports lag ~1 year
Unknown   │ 14 days │ 30 days│ Conservative default

Status Indicators:
🟢 FRESH   - Data is current
🟡 WARNING - Approaching staleness threshold
🔴 STALE   - Data exceeds acceptable lag
⚪ NO DATA - Series has no observations

Use this view for:
- Daily operational monitoring
- Alerting on stale data sources
- Data quality reporting';

-- ============================================================================
-- Grant permissions (optional - adjust based on your access control)
-- ============================================================================

-- Example: Grant read access to analytics role
-- GRANT USAGE ON SCHEMA analytics TO analytics_readonly;
-- GRANT SELECT ON ALL TABLES IN SCHEMA analytics TO analytics_readonly;

-- ============================================================================
-- Verification Queries (commented out - uncomment to test)
-- ============================================================================

-- Test FX normalization:
-- SELECT * FROM analytics.fx_rates_normalized LIMIT 10;

-- Test macro indicators:
-- SELECT * FROM analytics.macro_indicators_latest WHERE geography = 'USA';

-- Test data quality:
-- SELECT * FROM analytics.data_quality_dashboard WHERE freshness_status LIKE '🔴%';

-- ============================================================================
-- END OF VIEWS
-- ============================================================================