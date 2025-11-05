-- ============================================================================
-- Migration 005: TimescaleDB Business Logic (FIXED - No CTEs/Window Functions)
-- ============================================================================
-- Version: 005.1 (Fixed)
-- Date: 2025-11-05
-- Description: Continuous aggregates WITHOUT CTEs/window functions,
--              compression policies, and analytical functions
-- 
-- CRITICAL: TimescaleDB continuous aggregates do NOT support:
--   - CTEs (WITH clauses)
--   - Window functions (LAG, LEAD, ROW_NUMBER, etc.)
--   - Subqueries in SELECT
--
-- Solution: Use simple aggregations only, compute advanced metrics in functions
-- ============================================================================

-- ============================================================================
-- PART 0: ENABLE COMPRESSION ON HYPERTABLE
-- ============================================================================

-- Enable compression FIRST (required before adding compression policy)
ALTER TABLE timeseries.economic_observations SET (
    timescaledb.compress,
    timescaledb.compress_segmentby = 'series_id',
    timescaledb.compress_orderby = 'observation_date DESC'
);

-- ============================================================================
-- PART 1: CONTINUOUS AGGREGATES (Simple Aggregations Only)
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1.1: Daily FX Rate Summary (SIMPLIFIED - No CTEs)
-- ----------------------------------------------------------------------------

DROP MATERIALIZED VIEW IF EXISTS analytics.fx_daily_summary CASCADE;

CREATE MATERIALIZED VIEW analytics.fx_daily_summary
WITH (timescaledb.continuous) AS
SELECT
    time_bucket('1 day', observation_date) AS day,
    series_id,
    COUNT(*) AS observation_count,
    AVG(value) AS avg_rate,
    MIN(value) AS min_rate,
    MAX(value) AS max_rate,
    STDDEV(value) AS volatility,
    FIRST(value, observation_date) AS open_rate,
    LAST(value, observation_date) AS close_rate
FROM timeseries.economic_observations
GROUP BY day, series_id;

COMMENT ON MATERIALIZED VIEW analytics.fx_daily_summary IS
'Daily rate statistics for ALL series (not just FX).
Filter by series_type in queries: WHERE series_id IN (SELECT series_id FROM metadata.series_metadata WHERE series_type = ''FX'')';

SELECT add_continuous_aggregate_policy('analytics.fx_daily_summary',
    start_offset => INTERVAL '7 days',
    end_offset => INTERVAL '1 hour',
    schedule_interval => INTERVAL '1 hour');

-- ----------------------------------------------------------------------------
-- 1.2: Monthly Macro Indicator Aggregates (SIMPLIFIED - No Window Functions)
-- ----------------------------------------------------------------------------

DROP MATERIALIZED VIEW IF EXISTS analytics.macro_monthly_summary CASCADE;

CREATE MATERIALIZED VIEW analytics.macro_monthly_summary
WITH (timescaledb.continuous) AS
SELECT
    time_bucket('1 month', observation_date) AS month,
    series_id,
    COUNT(*) AS observation_count,
    AVG(value) AS avg_value,
    MIN(value) AS min_value,
    MAX(value) AS max_value,
    STDDEV(value) AS stddev_value,
    FIRST(value, observation_date) AS month_start_value,
    LAST(value, observation_date) AS month_end_value
FROM timeseries.economic_observations
GROUP BY month, series_id;

COMMENT ON MATERIALIZED VIEW analytics.macro_monthly_summary IS
'Monthly macro aggregates. Compute MoM change in application layer or via function.';

SELECT add_continuous_aggregate_policy('analytics.macro_monthly_summary',
    start_offset => INTERVAL '6 months',
    end_offset => INTERVAL '1 day',
    schedule_interval => INTERVAL '1 day');

-- ----------------------------------------------------------------------------
-- 1.3: Weekly Interest Rate Trends (SIMPLIFIED)
-- ----------------------------------------------------------------------------

DROP MATERIALIZED VIEW IF EXISTS analytics.interest_rate_weekly CASCADE;

CREATE MATERIALIZED VIEW analytics.interest_rate_weekly
WITH (timescaledb.continuous) AS
SELECT
    time_bucket('1 week', observation_date) AS week,
    series_id,
    AVG(value) AS avg_rate,
    MIN(value) AS min_rate,
    MAX(value) AS max_rate,
    LAST(value, observation_date) AS week_end_rate
FROM timeseries.economic_observations
GROUP BY week, series_id;

COMMENT ON MATERIALIZED VIEW analytics.interest_rate_weekly IS
'Weekly interest rate aggregates. Compute weekly change via function.';

SELECT add_continuous_aggregate_policy('analytics.interest_rate_weekly',
    start_offset => INTERVAL '3 months',
    end_offset => INTERVAL '1 day',
    schedule_interval => INTERVAL '1 day');

-- ============================================================================
-- PART 2: COMPRESSION POLICY
-- ============================================================================

SELECT add_compression_policy('timeseries.economic_observations',
    compress_after => INTERVAL '30 days',
    if_not_exists => TRUE);

COMMENT ON TABLE timeseries.economic_observations IS
'TimescaleDB hypertable with compression enabled (30-day threshold).';

-- ============================================================================
-- PART 3: HELPER FUNCTIONS FOR COMPUTED METRICS
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 3.1: Compute Daily Change (since continuous aggregate can't do it)
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION analytics.compute_fx_daily_change(
    p_series_id INTEGER,
    p_date DATE
)
RETURNS NUMERIC AS $$
DECLARE
    v_close NUMERIC;
    v_open NUMERIC;
BEGIN
    SELECT close_rate, open_rate INTO v_close, v_open
    FROM analytics.fx_daily_summary
    WHERE series_id = p_series_id
      AND day = p_date;
    
    RETURN v_close - v_open;
END;
$$ LANGUAGE plpgsql STABLE;

COMMENT ON FUNCTION analytics.compute_fx_daily_change IS
'Compute daily change from continuous aggregate.
Example: SELECT analytics.compute_fx_daily_change(42, ''2024-11-04'');';

-- ----------------------------------------------------------------------------
-- 3.2: Compute Month-over-Month Change
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION analytics.compute_mom_change(
    p_series_id INTEGER,
    p_month DATE
)
RETURNS TABLE (
    month DATE,
    current_value NUMERIC,
    previous_value NUMERIC,
    mom_change NUMERIC,
    mom_change_pct NUMERIC
) AS $$
BEGIN
    RETURN QUERY
    WITH current_month AS (
        SELECT month_end_value
        FROM analytics.macro_monthly_summary
        WHERE series_id = p_series_id
          AND month = DATE_TRUNC('month', p_month)
    ),
    previous_month AS (
        SELECT month_end_value
        FROM analytics.macro_monthly_summary
        WHERE series_id = p_series_id
          AND month = DATE_TRUNC('month', p_month) - INTERVAL '1 month'
    )
    SELECT
        DATE_TRUNC('month', p_month)::DATE,
        cm.month_end_value,
        pm.month_end_value,
        cm.month_end_value - pm.month_end_value,
        CASE
            WHEN pm.month_end_value != 0
            THEN ROUND(100.0 * (cm.month_end_value - pm.month_end_value) / pm.month_end_value, 2)
            ELSE NULL
        END
    FROM current_month cm
    CROSS JOIN previous_month pm;
END;
$$ LANGUAGE plpgsql STABLE;

COMMENT ON FUNCTION analytics.compute_mom_change IS
'Compute month-over-month change from continuous aggregate.
Example: SELECT * FROM analytics.compute_mom_change(42, ''2024-11-01'');';

-- ============================================================================
-- PART 4: ANALYTICAL FUNCTIONS (Reusable Business Logic)
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 4.1: Calculate Year-over-Year Growth
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION analytics.calculate_yoy_growth(
    p_series_id INTEGER,
    p_date DATE
)
RETURNS TABLE (
    series_id INTEGER,
    observation_date DATE,
    current_value NUMERIC,
    value_year_ago NUMERIC,
    yoy_change_pct NUMERIC,
    yoy_change_absolute NUMERIC
) AS $$
BEGIN
    RETURN QUERY
    WITH current_obs AS (
        SELECT
            eo.series_id,
            eo.observation_date,
            eo.value AS current_value
        FROM timeseries.economic_observations eo
        WHERE eo.series_id = p_series_id
          AND eo.observation_date = p_date
    ),
    year_ago_obs AS (
        SELECT
            eo.value AS value_year_ago
        FROM timeseries.economic_observations eo
        WHERE eo.series_id = p_series_id
          AND eo.observation_date = p_date - INTERVAL '1 year'
    )
    SELECT
        co.series_id,
        co.observation_date,
        co.current_value,
        yao.value_year_ago,
        CASE
            WHEN yao.value_year_ago IS NOT NULL AND yao.value_year_ago != 0
            THEN ROUND(100.0 * (co.current_value - yao.value_year_ago) / yao.value_year_ago, 2)
            ELSE NULL
        END AS yoy_change_pct,
        CASE
            WHEN yao.value_year_ago IS NOT NULL
            THEN ROUND((co.current_value - yao.value_year_ago)::numeric, 2)
            ELSE NULL
        END AS yoy_change_absolute
    FROM current_obs co
    CROSS JOIN year_ago_obs yao;
END;
$$ LANGUAGE plpgsql STABLE;

COMMENT ON FUNCTION analytics.calculate_yoy_growth IS
'Calculate year-over-year growth for any series and date.
Example: SELECT * FROM analytics.calculate_yoy_growth(42, ''2024-10-01'');';

-- ----------------------------------------------------------------------------
-- 4.2: Get Latest N Observations for Series
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION analytics.get_latest_observations(
    p_series_id INTEGER,
    p_limit INTEGER DEFAULT 10
)
RETURNS TABLE (
    observation_date DATE,
    value NUMERIC,
    days_ago INTEGER
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        eo.observation_date,
        eo.value,
        (CURRENT_DATE - eo.observation_date)::INTEGER AS days_ago
    FROM timeseries.economic_observations eo
    WHERE eo.series_id = p_series_id
      AND eo.value IS NOT NULL
    ORDER BY eo.observation_date DESC
    LIMIT p_limit;
END;
$$ LANGUAGE plpgsql STABLE;

COMMENT ON FUNCTION analytics.get_latest_observations IS
'Fetch N most recent observations for a series.
Example: SELECT * FROM analytics.get_latest_observations(42, 5);';

-- ----------------------------------------------------------------------------
-- 4.3: Calculate Moving Average
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION analytics.calculate_moving_average(
    p_series_id INTEGER,
    p_date DATE,
    p_window_days INTEGER DEFAULT 30
)
RETURNS NUMERIC AS $$
DECLARE
    v_avg NUMERIC;
BEGIN
    SELECT AVG(value) INTO v_avg
    FROM timeseries.economic_observations
    WHERE series_id = p_series_id
      AND observation_date BETWEEN (p_date - p_window_days) AND p_date
      AND value IS NOT NULL;
    
    RETURN ROUND(v_avg, 4);
END;
$$ LANGUAGE plpgsql STABLE;

COMMENT ON FUNCTION analytics.calculate_moving_average IS
'Calculate simple moving average over N-day window.
Example: SELECT analytics.calculate_moving_average(42, ''2024-10-01'', 30);';

-- ----------------------------------------------------------------------------
-- 4.4: Check Data Staleness
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION analytics.check_data_staleness(
    p_series_id INTEGER
)
RETURNS TABLE (
    series_id INTEGER,
    source_series_id VARCHAR,
    series_name VARCHAR,
    last_observation_date DATE,
    days_since_update INTEGER,
    frequency VARCHAR,
    status TEXT
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        sm.series_id,
        sm.source_series_id,
        sm.series_name,
        MAX(eo.observation_date) AS last_observation_date,
        (CURRENT_DATE - MAX(eo.observation_date))::INTEGER AS days_since_update,
        sm.frequency,
        CASE
            WHEN sm.frequency = 'D' AND (CURRENT_DATE - MAX(eo.observation_date)) > 7 THEN '🔴 STALE'
            WHEN sm.frequency = 'W' AND (CURRENT_DATE - MAX(eo.observation_date)) > 14 THEN '🔴 STALE'
            WHEN sm.frequency = 'M' AND (CURRENT_DATE - MAX(eo.observation_date)) > 60 THEN '🔴 STALE'
            WHEN sm.frequency = 'Q' AND (CURRENT_DATE - MAX(eo.observation_date)) > 120 THEN '🔴 STALE'
            WHEN sm.frequency = 'D' AND (CURRENT_DATE - MAX(eo.observation_date)) > 3 THEN '🟡 WARNING'
            WHEN sm.frequency = 'W' AND (CURRENT_DATE - MAX(eo.observation_date)) > 7 THEN '🟡 WARNING'
            WHEN sm.frequency = 'M' AND (CURRENT_DATE - MAX(eo.observation_date)) > 30 THEN '🟡 WARNING'
            ELSE '🟢 FRESH'
        END AS status
    FROM metadata.series_metadata sm
    LEFT JOIN timeseries.economic_observations eo ON sm.series_id = eo.series_id
    WHERE sm.series_id = p_series_id
    GROUP BY sm.series_id, sm.source_series_id, sm.series_name, sm.frequency;
END;
$$ LANGUAGE plpgsql STABLE;

COMMENT ON FUNCTION analytics.check_data_staleness IS
'Check if series data is stale based on frequency-aware thresholds.
Example: SELECT * FROM analytics.check_data_staleness(42);';

-- ============================================================================
-- PART 5: INDEXES
-- ============================================================================

CREATE INDEX IF NOT EXISTS idx_fx_daily_summary_day_series
    ON analytics.fx_daily_summary (day DESC, series_id);

CREATE INDEX IF NOT EXISTS idx_macro_monthly_summary_month_series
    ON analytics.macro_monthly_summary (month DESC, series_id);

CREATE INDEX IF NOT EXISTS idx_interest_weekly_week_series
    ON analytics.interest_rate_weekly (week DESC, series_id);

-- ============================================================================
-- VERIFICATION
-- ============================================================================

DO $$
DECLARE
    v_cagg_count INTEGER;
    v_compression_enabled BOOLEAN;
    v_function_count INTEGER;
BEGIN
    -- Check continuous aggregates
    SELECT COUNT(*) INTO v_cagg_count
    FROM timescaledb_information.continuous_aggregates
    WHERE view_schema = 'analytics';
    
    IF v_cagg_count = 3 THEN
        RAISE NOTICE '✅ Continuous aggregates created: %', v_cagg_count;
    ELSE
        RAISE WARNING '⚠️  Expected 3 continuous aggregates, found %', v_cagg_count;
    END IF;

    -- Check compression
    SELECT compression_enabled INTO v_compression_enabled
    FROM timescaledb_information.hypertables
    WHERE hypertable_name = 'economic_observations';
    
    IF v_compression_enabled THEN
        RAISE NOTICE '✅ Compression enabled';
    ELSE
        RAISE WARNING '⚠️  Compression not enabled';
    END IF;

    -- Check functions
    SELECT COUNT(*) INTO v_function_count
    FROM pg_proc p
    JOIN pg_namespace n ON p.pronamespace = n.oid
    WHERE n.nspname = 'analytics'
      AND p.proname IN ('calculate_yoy_growth', 'get_latest_observations', 
                        'calculate_moving_average', 'check_data_staleness',
                        'compute_fx_daily_change', 'compute_mom_change');
    
    IF v_function_count = 6 THEN
        RAISE NOTICE '✅ Analytical functions created: %', v_function_count;
    ELSE
        RAISE WARNING '⚠️  Expected 6 functions, found %', v_function_count;
    END IF;
END $$;

-- ============================================================================
-- USAGE NOTES
-- ============================================================================
--
-- Why No Window Functions in Continuous Aggregates?
-- -------------------------------------------------
-- TimescaleDB continuous aggregates are optimized for incremental refresh.
-- Window functions like LAG() require looking at neighboring rows, which
-- breaks the incremental model.
--
-- Solution: Compute derived metrics (MoM change, daily change) either:
-- 1. In application layer (fetch two rows, subtract)
-- 2. Via helper functions (compute_mom_change, compute_fx_daily_change)
-- 3. In regular views (non-continuous) that query the continuous aggregate
--
-- Trade-off: Slightly more work in application, but continuous aggregates
-- refresh much faster (10-100x) than full table scans.
--
-- ============================================================================
-- END OF MIGRATION 005 (FIXED)
-- ============================================================================