-- ============================================================================
-- Advanced Analytics Views
-- ============================================================================

-- View 1: Currency Strength Index
CREATE OR REPLACE VIEW analytics.currency_strength_index AS
WITH base_rates AS (
    SELECT
        observation_date,
        source_series_id,
        usd_per_fx,
        -- Calculate percentage change from 30 days ago
        LAG(usd_per_fx, 30) OVER (PARTITION BY source_series_id ORDER BY observation_date) as value_30d_ago
    FROM analytics.fx_rates_normalized
    WHERE source_series_id IN ('FXEURCAD', 'FXGBPCAD', 'FXJPYCAD', 'FXUSDCAD')
)
SELECT
    observation_date,
    source_series_id,
    usd_per_fx as current_rate,
    value_30d_ago,
    ROUND(100.0 * (usd_per_fx - value_30d_ago) / NULLIF(value_30d_ago, 0), 2) as pct_change_30d,
    CASE
        WHEN usd_per_fx > value_30d_ago THEN '📈 Strengthening'
        WHEN usd_per_fx < value_30d_ago THEN '📉 Weakening'
        ELSE '➡️ Stable'
    END as trend
FROM base_rates
WHERE value_30d_ago IS NOT NULL;

-- View 2: FX Volatility Monitor
CREATE OR REPLACE VIEW analytics.fx_volatility AS
WITH daily_changes AS (
    SELECT
        observation_date,
        source_series_id,
        usd_per_fx,
        LAG(usd_per_fx) OVER (PARTITION BY source_series_id ORDER BY observation_date) as prev_rate,
        ABS(usd_per_fx - LAG(usd_per_fx) OVER (PARTITION BY source_series_id ORDER BY observation_date))
            / NULLIF(LAG(usd_per_fx) OVER (PARTITION BY source_series_id ORDER BY observation_date), 0) as daily_change_pct
    FROM analytics.fx_rates_normalized
)
SELECT
    source_series_id,
    COUNT(*) as trading_days,
    ROUND(AVG(daily_change_pct * 100), 4) as avg_daily_move_pct,
    ROUND(STDDEV(daily_change_pct * 100), 4) as volatility_stddev,
    ROUND(MAX(daily_change_pct * 100), 4) as max_daily_move_pct,
    MIN(observation_date) as period_start,
    MAX(observation_date) as period_end
FROM daily_changes
WHERE observation_date >= CURRENT_DATE - INTERVAL '90 days'
  AND daily_change_pct IS NOT NULL
GROUP BY source_series_id;
