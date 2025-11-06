-- ============================================================================
-- Migration 006: PostGIS Geospatial Business Logic (FIXED)
-- ============================================================================
-- Version: 006.1 (Fixed - Geography Casting)
-- Date: 2025-11-05
-- Description: Geospatial functions with proper geography→geometry casting
--
-- CRITICAL FIX: ST_Collect requires geometry, not geography
-- Solution: Cast geography::geometry where needed
-- ============================================================================

-- ============================================================================
-- PART 1: DISTANCE-BASED SERIES DISCOVERY
-- ============================================================================

CREATE OR REPLACE FUNCTION analytics.find_series_near_location(
    p_latitude NUMERIC,
    p_longitude NUMERIC,
    p_radius_km INTEGER DEFAULT 500
)
RETURNS TABLE (
    series_id INTEGER,
    source_series_id VARCHAR,
    series_name VARCHAR,
    series_type VARCHAR,
    geography VARCHAR,
    distance_km NUMERIC
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        sm.series_id,
        sm.source_series_id,
        sm.series_name,
        sm.series_type,
        sm.geography,
        ROUND((ST_Distance(
            sm.location,
            ST_GeogFromText('POINT(' || p_longitude || ' ' || p_latitude || ')')
        ) / 1000)::NUMERIC, 2) AS distance_km
    FROM metadata.series_metadata sm
    WHERE sm.location IS NOT NULL
      AND ST_DWithin(
          sm.location,
          ST_GeogFromText('POINT(' || p_longitude || ' ' || p_latitude || ')'),
          p_radius_km * 1000
      )
    ORDER BY distance_km;
END;
$$ LANGUAGE plpgsql STABLE;

COMMENT ON FUNCTION analytics.find_series_near_location IS
'Find all series within radius (km) of a lat/lon point.
Example: SELECT * FROM analytics.find_series_near_location(45.4215, -75.6972, 500);';

-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION analytics.find_nearest_series(
    p_latitude NUMERIC,
    p_longitude NUMERIC,
    p_limit INTEGER DEFAULT 10
)
RETURNS TABLE (
    series_id INTEGER,
    source_series_id VARCHAR,
    series_name VARCHAR,
    series_type VARCHAR,
    geography VARCHAR,
    distance_km NUMERIC,
    rank INTEGER
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        sm.series_id,
        sm.source_series_id,
        sm.series_name,
        sm.series_type,
        sm.geography,
        ROUND((ST_Distance(
            sm.location,
            ST_GeogFromText('POINT(' || p_longitude || ' ' || p_latitude || ')')
        ) / 1000)::NUMERIC, 2) AS distance_km,
        ROW_NUMBER() OVER (ORDER BY ST_Distance(
            sm.location,
            ST_GeogFromText('POINT(' || p_longitude || ' ' || p_latitude || ')')
        ))::INTEGER AS rank
    FROM metadata.series_metadata sm
    WHERE sm.location IS NOT NULL
    ORDER BY distance_km
    LIMIT p_limit;
END;
$$ LANGUAGE plpgsql STABLE;

COMMENT ON FUNCTION analytics.find_nearest_series IS
'Find N nearest series to a lat/lon point.
Example: SELECT * FROM analytics.find_nearest_series(40.7128, -74.0060, 5);';

-- ============================================================================
-- PART 2: REGIONAL AGGREGATIONS
-- ============================================================================

CREATE OR REPLACE FUNCTION analytics.series_by_geography()
RETURNS TABLE (
    geography VARCHAR,
    series_count BIGINT,
    series_types TEXT[],
    data_source_centers geography(POINT, 4326)[]
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        sm.geography,
        COUNT(*)::BIGINT AS series_count,
        ARRAY_AGG(DISTINCT sm.series_type ORDER BY sm.series_type) FILTER (WHERE sm.series_type IS NOT NULL) AS series_types,
        ARRAY_AGG(DISTINCT sm.location ORDER BY sm.location::TEXT) FILTER (WHERE sm.location IS NOT NULL) AS data_source_centers
    FROM metadata.series_metadata sm
    WHERE sm.geography IS NOT NULL
    GROUP BY sm.geography
    ORDER BY series_count DESC;
END;
$$ LANGUAGE plpgsql STABLE;

COMMENT ON FUNCTION analytics.series_by_geography IS
'Count series grouped by geography with aggregated metadata.
Example: SELECT * FROM analytics.series_by_geography();';

-- ----------------------------------------------------------------------------
-- FIXED: Cast geography to geometry for ST_Collect
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION analytics.series_type_centroid(
    p_series_type VARCHAR
)
RETURNS TABLE (
    series_type VARCHAR,
    series_count BIGINT,
    centroid_latitude NUMERIC,
    centroid_longitude NUMERIC,
    geography_list TEXT
) AS $$
DECLARE
    v_centroid geometry;  -- Changed from geography to geometry
BEGIN
    -- Calculate centroid (cast geography to geometry)
    SELECT ST_Centroid(ST_Collect(location::geometry))  -- CRITICAL FIX: Cast to geometry
    INTO v_centroid
    FROM metadata.series_metadata
    WHERE series_type = p_series_type
      AND location IS NOT NULL;

    -- Return results
    RETURN QUERY
    SELECT
        p_series_type,
        COUNT(*)::BIGINT,
        ROUND(ST_Y(v_centroid)::NUMERIC, 4) AS centroid_latitude,
        ROUND(ST_X(v_centroid)::NUMERIC, 4) AS centroid_longitude,
        STRING_AGG(DISTINCT geography, ', ' ORDER BY geography) AS geography_list
    FROM metadata.series_metadata
    WHERE series_type = p_series_type;
END;
$$ LANGUAGE plpgsql STABLE;

COMMENT ON FUNCTION analytics.series_type_centroid IS
'Calculate geographic centroid (center point) for a series type.
Example: SELECT * FROM analytics.series_type_centroid(''FX'');';

-- ============================================================================
-- PART 3: CROSS-BORDER ANALYTICS
-- ============================================================================

CREATE OR REPLACE FUNCTION analytics.distance_between_sources(
    p_source_1 VARCHAR,
    p_source_2 VARCHAR
)
RETURNS TABLE (
    source_1 VARCHAR,
    source_2 VARCHAR,
    distance_km NUMERIC,
    location_1 geography(POINT, 4326),
    location_2 geography(POINT, 4326)
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        ds1.source_name,
        ds2.source_name,
        ROUND((ST_Distance(
            sm1.location,
            sm2.location
        ) / 1000)::NUMERIC, 2) AS distance_km,
        sm1.location,
        sm2.location
    FROM metadata.data_sources ds1
    CROSS JOIN metadata.data_sources ds2
    JOIN LATERAL (
        SELECT location FROM metadata.series_metadata
        WHERE source_id = ds1.source_id AND location IS NOT NULL
        LIMIT 1
    ) sm1 ON true
    JOIN LATERAL (
        SELECT location FROM metadata.series_metadata
        WHERE source_id = ds2.source_id AND location IS NOT NULL
        LIMIT 1
    ) sm2 ON true
    WHERE ds1.source_name = p_source_1
      AND ds2.source_name = p_source_2;
END;
$$ LANGUAGE plpgsql STABLE;

COMMENT ON FUNCTION analytics.distance_between_sources IS
'Calculate distance between two data sources.
Example: SELECT * FROM analytics.distance_between_sources(''FRED'', ''VALET'');';

-- ============================================================================
-- PART 4: GEOSPATIAL VIEWS
-- ============================================================================

CREATE OR REPLACE VIEW analytics.series_map_data AS
SELECT
    sm.series_id,
    sm.source_series_id,
    sm.series_name,
    sm.series_type,
    sm.geography,
    ds.source_name,
    ST_Y(sm.location::geometry) AS latitude,
    ST_X(sm.location::geometry) AS longitude,
    (SELECT MAX(observation_date)
     FROM timeseries.economic_observations
     WHERE series_id = sm.series_id) AS last_updated,
    (SELECT COUNT(*)
     FROM timeseries.economic_observations
     WHERE series_id = sm.series_id) AS observation_count,
    ST_AsGeoJSON(sm.location)::JSON AS geojson
FROM metadata.series_metadata sm
JOIN metadata.data_sources ds ON sm.source_id = ds.source_id
WHERE sm.location IS NOT NULL
ORDER BY sm.geography, sm.series_type;

COMMENT ON VIEW analytics.series_map_data IS
'Pre-formatted geospatial data for map visualizations with lat/lon and GeoJSON.';

-- ----------------------------------------------------------------------------
-- FIXED: Cast geography to geometry for ST_Collect in view
-- ----------------------------------------------------------------------------

DROP VIEW IF EXISTS analytics.regional_clusters CASCADE;

CREATE OR REPLACE VIEW analytics.regional_clusters AS
SELECT
    sm.geography,
    sm.series_type,
    COUNT(*) AS series_count,
    ARRAY_AGG(sm.source_series_id ORDER BY sm.source_series_id) AS series_ids,
    -- CRITICAL FIX: Cast to geometry for ST_Collect
    ST_Y(ST_Centroid(ST_Collect(sm.location::geometry))::geometry) AS cluster_latitude,
    ST_X(ST_Centroid(ST_Collect(sm.location::geometry))::geometry) AS cluster_longitude,
    -- Bounding box
    ST_YMin(ST_Extent(sm.location::geometry)) AS bbox_south,
    ST_YMax(ST_Extent(sm.location::geometry)) AS bbox_north,
    ST_XMin(ST_Extent(sm.location::geometry)) AS bbox_west,
    ST_XMax(ST_Extent(sm.location::geometry)) AS bbox_east
FROM metadata.series_metadata sm
WHERE sm.location IS NOT NULL
GROUP BY sm.geography, sm.series_type
ORDER BY sm.geography, series_count DESC;

COMMENT ON VIEW analytics.regional_clusters IS
'Clustered series by geography and type with bounding boxes.';

-- ============================================================================
-- PART 5: INDEXES
-- ============================================================================

CREATE INDEX IF NOT EXISTS idx_series_geography_type
    ON metadata.series_metadata (geography, series_type)
    WHERE location IS NOT NULL;

COMMENT ON INDEX idx_series_geography_type IS
'Composite index for geography + series_type queries';

-- ============================================================================
-- VERIFICATION
-- ============================================================================

DO $$
DECLARE
    v_function_count INTEGER;
    v_view_count INTEGER;
    v_series_with_coords INTEGER;
BEGIN
    -- Check functions
    SELECT COUNT(*) INTO v_function_count
    FROM pg_proc p
    JOIN pg_namespace n ON p.pronamespace = n.oid
    WHERE n.nspname = 'analytics'
      AND p.proname IN (
          'find_series_near_location',
          'find_nearest_series',
          'series_by_geography',
          'series_type_centroid',
          'distance_between_sources'
      );

    IF v_function_count = 5 THEN
        RAISE NOTICE '✅ PostGIS functions created: %', v_function_count;
    ELSE
        RAISE WARNING '⚠️  Expected 5 PostGIS functions, found %', v_function_count;
    END IF;

    -- Check views
    SELECT COUNT(*) INTO v_view_count
    FROM pg_views
    WHERE schemaname = 'analytics'
      AND viewname IN ('series_map_data', 'regional_clusters');

    IF v_view_count = 2 THEN
        RAISE NOTICE '✅ PostGIS views created: %', v_view_count;
    ELSE
        RAISE WARNING '⚠️  Expected 2 PostGIS views, found %', v_view_count;
    END IF;

    -- Verify coordinates
    SELECT COUNT(*) INTO v_series_with_coords
    FROM metadata.series_metadata
    WHERE location IS NOT NULL;

    RAISE NOTICE '✅ Series with coordinates: %', v_series_with_coords;
END $$;

-- ============================================================================
-- TEST QUERIES
-- ============================================================================

-- Test 1: Find series near Ottawa
-- SELECT * FROM analytics.find_series_near_location(45.4215, -75.6972, 500);

-- Test 2: Find nearest to NYC
-- SELECT * FROM analytics.find_nearest_series(40.7128, -74.0060, 5);

-- Test 3: Count by geography
-- SELECT * FROM analytics.series_by_geography();

-- Test 4: FX centroid
-- SELECT * FROM analytics.series_type_centroid('FX');

-- Test 5: Distance FRED to Valet
-- SELECT * FROM analytics.distance_between_sources('FRED', 'VALET');

-- Test 6: Map data
-- SELECT * FROM analytics.series_map_data LIMIT 5;

-- Test 7: Regional clusters
-- SELECT * FROM analytics.regional_clusters;

-- ============================================================================
-- END OF MIGRATION 006 (FIXED)
-- ============================================================================
