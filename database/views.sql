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
-- VIEW: FX Rates Normalized (CORRECTED with Cross-Rate Calculations)
-- ============================================================================
-- Purpose: Standardize ALL FX rates to "USD per 1 unit of foreign currency"
-- 
-- Data Sources:
-- - FRED DEX* series: Some are USD-based, some are not
-- - Bank of Canada FX* series: ALL are CAD-based (require cross-rate conversion)
--
-- Key Fix: Non-USD rates now use date-aware cross-rate calculation
-- ============================================================================

CREATE OR REPLACE VIEW analytics.fx_rates_normalized AS
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
        (sm.source_series_id LIKE 'DEX%' OR sm.source_series_id LIKE 'FX%')
        AND eo.value IS NOT NULL
        AND eo.value != 0
),
-- Extract USD/CAD rate for cross-rate calculations
usd_cad_rates AS (
    SELECT 
        observation_date,
        -- FXUSDCAD is CAD per USD, so invert to get USD per CAD
        1.0 / raw_value as usd_per_cad
    FROM raw_fx
    WHERE source_series_id = 'FXUSDCAD'
),
-- Also get FRED's USD/CAD rate for cross-validation
fred_usd_cad AS (
    SELECT 
        observation_date,
        -- DEXCAUS is also CAD per USD, invert to get USD per CAD
        1.0 / raw_value as usd_per_cad
    FROM raw_fx
    WHERE source_series_id = 'DEXCAUS'
)
SELECT 
    rf.observation_date,
    rf.source_series_id,
    rf.series_id,
    rf.source_name,
    rf.raw_value,
    rf.geography,
    
    -- ========================================================================
    -- CRITICAL: Correct normalization to USD per FX
    -- ========================================================================
    CASE 
        -- ====================================================================
        -- Group 1: FRED rates already in USD per FX (no conversion needed)
        -- ====================================================================
        WHEN rf.source_series_id IN ('DEXUSEU', 'DEXUSUK', 'DEXUSAL', 'DEXUSNZ') 
            THEN rf.raw_value
        
        -- ====================================================================
        -- Group 2: FRED rates in FX per USD (simple inversion)
        -- ====================================================================
        WHEN rf.source_series_id IN ('DEXCAUS', 'DEXJPUS', 'DEXCHUS', 'DEXMXUS', 
                                      'DEXINUS', 'DEXKOUS', 'DEXSZUS', 'DEXTHUS',
                                      'DEXBZUS', 'DEXSFUS', 'DEXVZUS', 'DEXMAUS')
            THEN 1.0 / rf.raw_value
        
        -- ====================================================================
        -- Group 3: Bank of Canada USD/CAD (simple inversion)
        -- ====================================================================
        WHEN rf.source_series_id = 'FXUSDCAD'
            THEN 1.0 / rf.raw_value
        
        -- ====================================================================
        -- Group 4: Bank of Canada non-USD rates (CROSS-RATE CALCULATION)
        -- ====================================================================
        -- Formula: USD per FX = (CAD per FX) × (USD per CAD)
        -- Example: USD per EUR = (1.627 CAD/EUR) × (0.7164 USD/CAD) = 1.1656 USD/EUR
        -- ====================================================================
        WHEN rf.source_series_id LIKE 'FX%' AND rf.source_series_id != 'FXUSDCAD'
            THEN rf.raw_value * COALESCE(ucr.usd_per_cad, 0)
        
        -- Default: return raw value (shouldn't hit this)
        ELSE rf.raw_value
    END as usd_per_fx,
    
    -- ========================================================================
    -- Metadata: Transformation applied
    -- ========================================================================
    CASE 
        WHEN rf.source_series_id IN ('DEXUSEU', 'DEXUSUK', 'DEXUSAL', 'DEXUSNZ') 
            THEN 'none'
        WHEN rf.source_series_id IN ('DEXCAUS', 'DEXJPUS', 'DEXCHUS', 'DEXMXUS', 'FXUSDCAD')
            THEN 'inverted'
        WHEN rf.source_series_id LIKE 'FX%' AND rf.source_series_id != 'FXUSDCAD'
            THEN 'cross_rate'
        ELSE 'unknown'
    END as transformation_type,
    
    -- ========================================================================
    -- Human-readable description (CORRECTED)
    -- ========================================================================
    CASE 
        -- FRED: Native USD rates
        WHEN rf.source_series_id = 'DEXUSEU' THEN 'USD per EUR'
        WHEN rf.source_series_id = 'DEXUSUK' THEN 'USD per GBP'
        WHEN rf.source_series_id = 'DEXUSAL' THEN 'USD per AUD'
        WHEN rf.source_series_id = 'DEXUSNZ' THEN 'USD per NZD'
        
        -- FRED: Inverted rates
        WHEN rf.source_series_id = 'DEXCAUS' THEN 'USD per CAD (FRED)'
        WHEN rf.source_series_id = 'DEXJPUS' THEN 'USD per 100 JPY (FRED)'
        WHEN rf.source_series_id = 'DEXCHUS' THEN 'USD per CHF (FRED)'
        WHEN rf.source_series_id = 'DEXMXUS' THEN 'USD per MXN (FRED)'
        
        -- Bank of Canada: USD/CAD
        WHEN rf.source_series_id = 'FXUSDCAD' THEN 'USD per CAD (Bank of Canada)'
        
        -- Bank of Canada: Cross-rates (CORRECTED DESCRIPTIONS)
        WHEN rf.source_series_id = 'FXEURCAD' THEN 'USD per EUR (via CAD cross-rate)'
        WHEN rf.source_series_id = 'FXGBPCAD' THEN 'USD per GBP (via CAD cross-rate)'
        WHEN rf.source_series_id = 'FXJPYCAD' THEN 'USD per 100 JPY (via CAD cross-rate)'
        WHEN rf.source_series_id = 'FXCHFCAD' THEN 'USD per CHF (via CAD cross-rate)'
        WHEN rf.source_series_id = 'FXAUDCAD' THEN 'USD per AUD (via CAD cross-rate)'
        
        -- Fallback
        ELSE 'USD per ' || SUBSTRING(rf.source_series_id FROM 3)
    END as rate_description,
    
    -- Additional metadata for transparency
    ucr.usd_per_cad as usd_cad_rate_used,
    rf.raw_value as original_raw_value
    
FROM raw_fx rf
LEFT JOIN usd_cad_rates ucr ON rf.observation_date = ucr.observation_date
WHERE 
    -- Only include rows where we have USD/CAD rate for cross-rate calculations
    (rf.source_series_id NOT LIKE 'FX%' 
     OR rf.source_series_id = 'FXUSDCAD'
     OR (rf.source_series_id LIKE 'FX%' AND ucr.usd_per_cad IS NOT NULL));

COMMENT ON VIEW analytics.fx_rates_normalized IS 
'FX rates normalized to USD per 1 unit of foreign currency.

Transformation Methods:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
1. NONE: Already USD-based (FRED DEXUSEU, DEXUSUK, etc.)
   - Raw value = USD per FX
   
2. INVERTED: FX per USD → invert to get USD per FX
   - FRED DEXCAUS, DEXJPUS, etc.
   - Bank of Canada FXUSDCAD
   - Formula: usd_per_fx = 1 / raw_value
   
3. CROSS_RATE: CAD-based → convert via USD/CAD rate
   - Bank of Canada FXEURCAD, FXGBPCAD, FXJPYCAD, etc.
   - Formula: usd_per_fx = (CAD per FX) × (USD per CAD)
   - Example: FXEURCAD = 1.627 CAD/EUR × 0.7164 USD/CAD = 1.1656 USD/EUR
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Data Quality Notes:
- Cross-rate calculations require matching observation_date for USD/CAD
- Rows without USD/CAD rate on same date are excluded (rare for daily data)
- Column "usd_cad_rate_used" shows the USD/CAD rate applied for transparency

Always query this view for cross-currency analysis, never use raw data directly.';

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