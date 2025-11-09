-- Data Quality Dashboard View
CREATE OR REPLACE VIEW analytics.data_quality_dashboard AS
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
        CURRENT_DATE - MAX(eo.observation_date) as days_since_last_update
    FROM metadata.series_metadata sm
    JOIN metadata.data_sources ds ON sm.source_id = ds.source_id
    LEFT JOIN timeseries.economic_observations eo ON sm.series_id = eo.series_id
    GROUP BY sm.series_id, ds.source_name, sm.source_series_id, sm.series_name, sm.frequency, sm.geography
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
    days_since_last_update,
    CASE
        WHEN days_since_last_update IS NULL THEN 'NO DATA'
        WHEN days_since_last_update > 90 THEN 'STALE'
        WHEN days_since_last_update > 30 THEN 'WARNING'
        ELSE 'FRESH'
    END as freshness_status
FROM series_stats
ORDER BY days_since_last_update DESC NULLS LAST;
