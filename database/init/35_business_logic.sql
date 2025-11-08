CREATE EXTENSION IF NOT EXISTS timescaledb CASCADE;
DROP MATERIALIZED VIEW IF EXISTS analytics.fx_daily_summary CASCADE;
CREATE MATERIALIZED VIEW analytics.fx_daily_summary WITH (timescaledb.continuous) AS SELECT time_bucket('1 day', observation_date) AS day, series_id, AVG(value) AS avg_rate, MIN(value) AS min_rate, MAX(value) AS max_rate, FIRST(value, observation_date) AS open_rate, LAST(value, observation_date) AS close_rate FROM timeseries.economic_observations GROUP BY day, series_id WITH NO DATA;
SELECT add_continuous_aggregate_policy('analytics.fx_daily_summary', '7 days', '1 hour', '1 hour', if_not_exists => TRUE);
ALTER TABLE timeseries.economic_observations SET (timescaledb.compress, timescaledb.compress_segmentby = 'series_id');
SELECT add_compression_policy('timeseries.economic_observations', INTERVAL '30 days', if_not_exists => TRUE);
CREATE OR REPLACE FUNCTION analytics.get_latest_observations(p_series_id INTEGER, p_limit INTEGER DEFAULT 10) RETURNS TABLE (observation_date DATE, value NUMERIC) AS $$ BEGIN RETURN QUERY SELECT eo.observation_date, eo.value FROM timeseries.economic_observations eo WHERE eo.series_id = p_series_id AND eo.value IS NOT NULL ORDER BY eo.observation_date DESC LIMIT p_limit; END; $$ LANGUAGE plpgsql STABLE;
