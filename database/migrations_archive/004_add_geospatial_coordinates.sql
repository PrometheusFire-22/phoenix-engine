-- ============================================================================
-- Migration: Add Geospatial Coordinates
-- Version: 004
-- Date: 2025-11-05
-- Description: Populate latitude/longitude for series based on data source
-- ============================================================================

BEGIN;

-- ============================================================================
-- US Federal Economic Data (FRED)
-- Location: Washington, DC (Federal Reserve coordinates)
-- ============================================================================
UPDATE metadata.series_metadata
SET
    location = ST_GeogFromText('POINT(-77.0364 38.8951)'),  -- lon lat (PostGIS standard)
    geography = 'United States'
WHERE source_id = (SELECT source_id FROM metadata.data_sources WHERE source_name = 'FRED');

-- ============================================================================
-- Bank of Canada (Valet)
-- Location: Ottawa, Ontario, Canada
-- ============================================================================
UPDATE metadata.series_metadata
SET
    location = ST_GeogFromText('POINT(-75.6972 45.4215)'),  -- lon lat
    geography = 'Canada'
WHERE source_id = (SELECT source_id FROM metadata.data_sources WHERE source_name = 'VALET');

-- ============================================================================
-- Verify Updates
-- ============================================================================
DO $$
DECLARE
    total_series INTEGER;
    with_coords INTEGER;
BEGIN
    SELECT COUNT(*) INTO total_series FROM metadata.series_metadata;
    SELECT COUNT(*) INTO with_coords
    FROM metadata.series_metadata
    WHERE location IS NOT NULL;

    RAISE NOTICE 'Total series: %', total_series;
    RAISE NOTICE 'Series with coordinates: %', with_coords;
    RAISE NOTICE 'Coverage: %%%', ROUND(100.0 * with_coords / total_series, 1);
END $$;

COMMIT;

-- ============================================================================
-- Example Geospatial Queries
-- ============================================================================

-- Find all series within 100km of a location
-- SELECT
--     source_series_id,
--     series_name,
--     ST_Distance(
--         ST_MakePoint(longitude, latitude)::geography,
--         ST_MakePoint(-75.6972, 45.4215)::geography  -- Ottawa
--     ) / 1000 as distance_km
-- FROM metadata.series_metadata
-- WHERE latitude IS NOT NULL
-- ORDER BY distance_km
-- LIMIT 10;

-- Find series by country
-- SELECT country, COUNT(*) as series_count
-- FROM metadata.series_metadata
-- WHERE country IS NOT NULL
-- GROUP BY country
-- ORDER BY series_count DESC;
