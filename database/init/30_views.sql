CREATE OR REPLACE VIEW analytics.fx_rates_normalized AS
WITH raw_fx AS (SELECT eo.observation_date, sm.source_series_id, sm.series_id, eo.value as raw_value, ds.source_name FROM timeseries.economic_observations eo JOIN metadata.series_metadata sm ON eo.series_id = sm.series_id JOIN metadata.data_sources ds ON sm.source_id = ds.source_id WHERE (sm.source_series_id LIKE 'DEX%' OR sm.source_series_id LIKE 'FX%') AND eo.value IS NOT NULL AND eo.value != 0),
usd_cad_rates AS (SELECT observation_date, 1.0 / raw_value as usd_per_cad FROM raw_fx WHERE source_series_id = 'FXUSDCAD')
SELECT rf.observation_date, rf.source_series_id, rf.series_id, rf.source_name, rf.raw_value,
CASE WHEN rf.source_series_id IN ('DEXUSEU', 'DEXUSUK') THEN rf.raw_value WHEN rf.source_series_id IN ('DEXCAUS', 'DEXJPUS', 'DEXCHUS', 'FXUSDCAD') THEN 1.0 / rf.raw_value WHEN rf.source_series_id LIKE 'FX%' AND rf.source_series_id != 'FXUSDCAD' THEN rf.raw_value * COALESCE(ucr.usd_per_cad, 0) ELSE rf.raw_value END as usd_per_fx
FROM raw_fx rf LEFT JOIN usd_cad_rates ucr ON rf.observation_date = ucr.observation_date;
