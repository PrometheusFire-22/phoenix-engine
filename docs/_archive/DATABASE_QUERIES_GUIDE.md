# Project Chronos: Database Query Guide

## Quick Reference

### View Latest Values

```sql
-- All indicators with YoY growth
SELECT * FROM analytics.macro_indicators_latest
ORDER BY yoy_growth_pct DESC;

```

### Time-Series Charts

```sql
-- Daily FX rates for charting
SELECT day, avg_rate, volatility
FROM analytics.fx_daily_summary
WHERE series_id = (SELECT series_id FROM metadata.series_metadata WHERE source_series_id = 'FXUSDCAD')
  AND day >= CURRENT_DATE - INTERVAL '30 days'
ORDER BY day;

```

### Map Visualization

```sql
-- All series with coordinates
SELECT source_series_id, series_name, latitude, longitude, geojson
FROM analytics.series_map_data;

```

---

## TimescaleDB Queries

### 1. Continuous Aggregates (Fast!)

### FX Daily Summary

```sql
-- Get daily stats for USD/CAD
SELECT
    day,
    avg_rate,
    min_rate,
    max_rate,
    volatility,
    open_rate,
    close_rate
FROM analytics.fx_daily_summary
WHERE series_id = (SELECT series_id FROM metadata.series_metadata WHERE source_series_id = 'FXUSDCAD')
  AND day >= '2024-01-01'
ORDER BY day DESC;

```

**Use Case:** Dashboards, charts, volatility analysis

### Macro Monthly Summary

```sql
-- GDP monthly aggregates
SELECT
    month,
    avg_value,
    month_start_value,
    month_end_value
FROM analytics.macro_monthly_summary
WHERE series_id = (SELECT series_id FROM metadata.series_metadata WHERE source_series_id = 'GDP')
ORDER BY month DESC
LIMIT 12;

```

**Use Case:** Monthly reports, trend analysis

### Interest Rate Weekly

```sql
-- Fed Funds rate trends
SELECT
    week,
    avg_rate,
    week_end_rate
FROM analytics.interest_rate_weekly
WHERE series_id = (SELECT series_id FROM metadata.series_metadata WHERE source_series_id = 'FEDFUNDS')
  AND week >= CURRENT_DATE - INTERVAL '6 months'
ORDER BY week DESC;

```

**Use Case:** Rate monitoring, policy analysis

### 2. Analytical Functions

### Year-over-Year Growth

```sql
-- Calculate YoY growth for any series
SELECT * FROM analytics.calculate_yoy_growth(
    42,              -- series_id
    '2024-10-01'     -- date
);

```

**Returns:** current_value, value_year_ago, yoy_change_pct, yoy_change_absolute

### Latest Observations

```sql
-- Get 10 most recent values
SELECT * FROM analytics.get_latest_observations(
    42,   -- series_id
    10    -- limit
);

```

**Returns:** observation_date, value, days_ago

### Moving Average

```sql
-- 30-day moving average
SELECT analytics.calculate_moving_average(
    42,              -- series_id
    CURRENT_DATE,    -- date
    30               -- window_days
);

```

**Returns:** Smoothed value

### Data Staleness Check

```sql
-- Check if data is fresh
SELECT * FROM analytics.check_data_staleness(42);

```

**Returns:** last_observation_date, days_since_update, status (🟢 FRESH / 🟡 WARNING / 🔴 STALE)

---

## PostGIS Queries

### 1. Distance-Based Discovery

### Find Series Within Radius

```sql
-- All indicators within 500km of Toronto
SELECT * FROM analytics.find_series_near_location(
    43.6532,  -- Toronto latitude
    -79.3832, -- Toronto longitude
    500       -- radius in km
)
ORDER BY distance_km;

```

**Use Case:** Regional analysis, proximity search

### Find Nearest Series

```sql
-- 10 nearest indicators to New York
SELECT * FROM analytics.find_nearest_series(
    40.7128,  -- NYC latitude
    -74.0060, -- NYC longitude
    10        -- limit
);

```

**Use Case:** Location-based recommendations

### 2. Regional Aggregations

### Series by Geography

```sql
-- Count indicators by country
SELECT
    geography,
    series_count,
    series_types
FROM analytics.series_by_geography();

```

**Returns:** United States (38 series), Canada (14 series)

### Geographic Centroid

```sql
-- Center point of all FX indicators
SELECT * FROM analytics.series_type_centroid('FX');

```

**Returns:** centroid_latitude, centroid_longitude, geography_list

### Distance Between Sources

```sql
-- Distance between FRED (DC) and Valet (Ottawa)
SELECT * FROM analytics.distance_between_sources('FRED', 'VALET');

```

**Returns:** ~600 km

### 3. Map Views

### Series Map Data (For Leaflet/Mapbox)

```sql
-- Get all series for map markers
SELECT
    source_series_id,
    series_name,
    latitude,
    longitude,
    geojson,
    last_updated,
    observation_count
FROM analytics.series_map_data
WHERE series_type = 'FX';

```

**Use Case:** Map visualization with popups

### Regional Clusters

```sql
-- Cluster series by location
SELECT
    geography,
    series_type,
    series_count,
    cluster_latitude,
    cluster_longitude,
    bbox_north,
    bbox_south,
    bbox_east,
    bbox_west
FROM analytics.regional_clusters;

```

**Use Case:** Map clustering, zoom-to-fit

---

## pgvector Queries

### Semantic Search

### Find Similar Indicators

```sql
-- Query vector (from generate_embeddings.py)
WITH query_vector AS (
    SELECT '[0.123, -0.456, ...]'::vector AS embedding
)
SELECT
    source_series_id,
    series_name,
    1 - (description_embedding <=> (SELECT embedding FROM query_vector)) as similarity
FROM metadata.series_metadata
WHERE description_embedding IS NOT NULL
ORDER BY similarity DESC
LIMIT 10;

```

**Use Case:** "More like this" recommendations

---

## Apache AGE Queries (Manual Population Required)

### Example Cypher Queries

### Find Indicators by Type

```sql
LOAD 'age';
SET search_path = ag_catalog, "$user", public;

SELECT * FROM cypher('economic_graph', $$
    MATCH (i:Indicator {type: 'FX'})
    RETURN i.name, i.geography
    LIMIT 10
$$) as (name agtype, geography agtype);

```

### Find Influences

```sql
SELECT * FROM cypher('economic_graph', $$
    MATCH (source)-[:INFLUENCES]->(target:Indicator {type: 'FX'})
    RETURN source.name, target.name
$$) as (source agtype, target agtype);

```

---

## Performance Tips

### DO:

- ✅ Query continuous aggregates instead of raw observations
- ✅ Use indexed columns (series_id, observation_date)
- ✅ Filter by date ranges to limit scans
- ✅ Use helper functions for common calculations

### DON'T:

- ❌ Full table scans on timeseries.economic_observations
- ❌ Complex calculations in WHERE clauses
- ❌ Unfiltered JOINs across large tables

### Example: BAD vs GOOD

```sql
-- ❌ BAD: Full table scan
SELECT AVG(value)
FROM timeseries.economic_observations
WHERE series_id = 42;

-- ✅ GOOD: Use continuous aggregate
SELECT AVG(avg_rate)
FROM analytics.fx_daily_summary
WHERE series_id = 42;

```

---

## Common Patterns

### Dashboard: Latest Values

```sql
SELECT
    sm.series_name,
    lo.value AS latest_value,
    lo.observation_date,
    yoy.yoy_change_pct
FROM metadata.series_metadata sm
CROSS JOIN LATERAL analytics.get_latest_observations(sm.series_id, 1) lo
CROSS JOIN LATERAL analytics.calculate_yoy_growth(sm.series_id, lo.observation_date) yoy
WHERE sm.series_type = 'Macro'
ORDER BY sm.series_name;

```

### Chart: 30-Day Trend

```sql
SELECT day, avg_rate
FROM analytics.fx_daily_summary
WHERE series_id = X
  AND day >= CURRENT_DATE - INTERVAL '30 days'
ORDER BY day;

```

### Map: All Series

```sql
SELECT * FROM analytics.series_map_data;

```
